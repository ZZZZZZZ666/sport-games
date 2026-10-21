#include "ble_service.h"

#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "protocol.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char* TAG = "ble";

static const ble_uuid128_t s_svc_uuid = BLE_UUID128_INIT(RS_UUID128(0x00));
static const ble_uuid128_t s_imu_uuid = BLE_UUID128_INIT(RS_UUID128(0x01));
static const ble_uuid128_t s_input_uuid = BLE_UUID128_INIT(RS_UUID128(0x02));
static const ble_uuid128_t s_status_uuid = BLE_UUID128_INIT(RS_UUID128(0x03));
static const ble_uuid128_t s_cmd_uuid = BLE_UUID128_INIT(RS_UUID128(0x04));

static uint16_t s_imu_handle, s_input_handle, s_status_handle, s_cmd_handle;
static volatile uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static volatile uint16_t s_mtu = 23;
static volatile bool s_sub_imu, s_sub_input, s_sub_status;
static uint8_t s_own_addr_type;
static char s_name[24];
static ble_cmd_cb_t s_on_command;

static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;
static uint8_t s_input_val[16];
static uint16_t s_input_len;
static uint8_t s_status_val[16];
static uint16_t s_status_len;

static void advertise(void);

static int chr_access(uint16_t conn_handle, uint16_t attr_handle, struct ble_gatt_access_ctxt* ctxt, void* arg)
{
    (void)conn_handle;
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR)
    {
        uint8_t buf[16];
        uint16_t len = 0;
        portENTER_CRITICAL(&s_lock);
        if (attr_handle == s_input_handle)
        {
            len = s_input_len;
            memcpy(buf, s_input_val, len);
        }
        else if (attr_handle == s_status_handle)
        {
            len = s_status_len;
            memcpy(buf, s_status_val, len);
        }
        portEXIT_CRITICAL(&s_lock);
        return os_mbuf_append(ctxt->om, buf, len) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR && attr_handle == s_cmd_handle)
    {
        uint8_t buf[256];
        uint16_t len = 0;
        if (ble_hs_mbuf_to_flat(ctxt->om, buf, sizeof(buf), &len) != 0)
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        if (s_on_command && len > 0)
            s_on_command(buf, len);
        return 0;
    }
    return BLE_ATT_ERR_UNLIKELY;
}

static const struct ble_gatt_svc_def s_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {.uuid = &s_imu_uuid.u, .access_cb = chr_access, .flags = BLE_GATT_CHR_F_NOTIFY, .val_handle = &s_imu_handle},
                {.uuid = &s_input_uuid.u,
                 .access_cb = chr_access,
                 .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                 .val_handle = &s_input_handle},
                {.uuid = &s_status_uuid.u,
                 .access_cb = chr_access,
                 .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                 .val_handle = &s_status_handle},
                {.uuid = &s_cmd_uuid.u,
                 .access_cb = chr_access,
                 .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
                 .val_handle = &s_cmd_handle},
                {0},
            },
    },
    {0},
};

static int gap_event(struct ble_gap_event* event, void* arg)
{
    (void)arg;
    switch (event->type)
    {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0)
        {
            s_conn = event->connect.conn_handle;
            ESP_LOGI(TAG, "connected");
            // Ask for a short connection interval (7.5-15 ms) and a large MTU.
            struct ble_gap_upd_params params = {
                .itvl_min = 6,
                .itvl_max = 12,
                .latency = 0,
                .supervision_timeout = 400,
                .min_ce_len = 0,
                .max_ce_len = 0,
            };
            ble_gap_update_params(s_conn, &params);
            ble_gattc_exchange_mtu(s_conn, NULL, NULL);
        }
        else
        {
            advertise();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnected, reason %d", event->disconnect.reason);
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        s_mtu = 23;
        s_sub_imu = s_sub_input = s_sub_status = false;
        advertise();
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (s_conn == BLE_HS_CONN_HANDLE_NONE)
            advertise();
        return 0;

    case BLE_GAP_EVENT_MTU:
        s_mtu = event->mtu.value;
        ESP_LOGI(TAG, "mtu %d", s_mtu);
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_imu_handle)
            s_sub_imu = event->subscribe.cur_notify;
        else if (event->subscribe.attr_handle == s_input_handle)
            s_sub_input = event->subscribe.cur_notify;
        else if (event->subscribe.attr_handle == s_status_handle)
            s_sub_status = event->subscribe.cur_notify;
        return 0;

    default:
        return 0;
    }
}

static void advertise(void)
{
    struct ble_hs_adv_fields fields;
    memset(&fields, 0, sizeof(fields));
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = &s_svc_uuid;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0)
    {
        ESP_LOGE(TAG, "adv fields rc=%d", rc);
        return;
    }

    struct ble_hs_adv_fields rsp;
    memset(&rsp, 0, sizeof(rsp));
    rsp.name = (const uint8_t*)s_name;
    rsp.name_len = strlen(s_name);
    rsp.name_is_complete = 1;
    rsp.tx_pwr_lvl_is_present = 1;
    rsp.tx_pwr_lvl = BLE_HS_ADV_TX_PWR_LVL_AUTO;
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0)
    {
        ESP_LOGE(TAG, "scan rsp rc=%d", rc);
        return;
    }

    struct ble_gap_adv_params adv;
    memset(&adv, 0, sizeof(adv));
    adv.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv.disc_mode = BLE_GAP_DISC_MODE_GEN;
    adv.itvl_min = BLE_GAP_ADV_ITVL_MS(40);
    adv.itvl_max = BLE_GAP_ADV_ITVL_MS(60);
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &adv, gap_event, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY)
        ESP_LOGE(TAG, "adv start rc=%d", rc);
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own_addr_type);
    advertise();
    ESP_LOGI(TAG, "advertising as %s", s_name);
}

static void on_reset(int reason) { ESP_LOGW(TAG, "host reset, reason %d", reason); }

static void host_task(void* param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void ble_service_start(const char* name, ble_cmd_cb_t on_command)
{
    strncpy(s_name, name, sizeof(s_name) - 1);
    s_on_command = on_command;

    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    ESP_ERROR_CHECK(ble_gatts_count_cfg(s_services));
    ESP_ERROR_CHECK(ble_gatts_add_svcs(s_services));
    ble_svc_gap_device_name_set(s_name);
    ble_att_set_preferred_mtu(247);

    nimble_port_freertos_init(host_task);
}

bool ble_service_connected(void) { return s_conn != BLE_HS_CONN_HANDLE_NONE; }

uint16_t ble_service_mtu(void) { return s_mtu; }

static bool notify(uint16_t handle, const void* data, uint16_t len)
{
    uint16_t conn = s_conn;
    if (conn == BLE_HS_CONN_HANDLE_NONE)
        return false;
    struct os_mbuf* om = ble_hs_mbuf_from_flat(data, len);
    if (om == NULL)
        return false;
    return ble_gatts_notify_custom(conn, handle, om) == 0;  // consumes om
}

bool ble_service_notify_imu(const void* data, uint16_t len)
{
    if (!s_sub_imu || len + 3 > s_mtu)
        return false;
    return notify(s_imu_handle, data, len);
}

static void store(uint8_t* dst, uint16_t* dst_len, const void* data, uint16_t len)
{
    if (len > 16)
        len = 16;
    portENTER_CRITICAL(&s_lock);
    memcpy(dst, data, len);
    *dst_len = len;
    portEXIT_CRITICAL(&s_lock);
}

bool ble_service_update_input(const void* data, uint16_t len)
{
    store(s_input_val, &s_input_len, data, len);
    return s_sub_input && notify(s_input_handle, data, len);
}

bool ble_service_update_status(const void* data, uint16_t len)
{
    store(s_status_val, &s_status_len, data, len);
    return s_sub_status && notify(s_status_handle, data, len);
}
