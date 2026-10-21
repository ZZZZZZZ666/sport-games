class_name RSTiltStick
extends RefCounted
## Turns how far a controller is tilted away from a captured "level" pose into a 2-axis stick.
## Any grip works (remote-style with the screen up, or upright with the screen facing the
## player): capture() defines level, then tipping the top away from you pushes the stick
## forward and tipping it to the right pushes it right. Only the tilt against gravity is used,
## so gyro yaw drift never moves the stick.

var max_roll := deg_to_rad(45.0)   ## tilt for a full left/right stick
var max_pitch := deg_to_rad(35.0)  ## tilt for a full forward/back stick
var deadzone := deg_to_rad(3.0)

var _neutral := Quaternion.IDENTITY
var _up_body := Vector3.UP        ## body vector that pointed up when captured
var _right0 := Vector3.RIGHT      ## horizontal "right" when captured, world frame


func capture(q: Quaternion) -> void:
	_neutral = q
	_up_body = q.inverse() * Vector3.UP
	var r := q * Vector3.RIGHT
	r.y = 0.0
	_right0 = r.normalized() if r.length() > 0.1 else Vector3.RIGHT


func tilt(q: Quaternion) -> Vector2:
	## Radians: x = tilted to the right, y = tilted back toward the player (pull = nose up).
	var w := q * _up_body
	# Split the change since capture into a tilt (swing of the old "up") and a turn about the
	# vertical (twist). Measuring the tilt in the twisted frame keeps "right" = the device's
	# right even after the player turns around.
	var swing := Quaternion(Vector3.UP, w) if w.y > -0.99 else Quaternion.IDENTITY
	var twist := swing.inverse() * (q * _neutral.inverse())
	var right := twist * _right0
	right.y = 0.0
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	return Vector2(atan2(w.dot(right), w.y), -atan2(w.dot(fwd), w.y))


func stick(q: Quaternion) -> Vector2:
	## -1..1 per axis, with a small deadzone around level.
	var t := tilt(q)
	return Vector2(_axis(t.x, max_roll), _axis(t.y, max_pitch))


func _axis(angle: float, full: float) -> float:
	var m := maxf(absf(angle) - deadzone, 0.0) / (full - deadzone)
	return clampf(signf(angle) * m, -1.0, 1.0)


func frame(q: Quaternion) -> Array[Vector3]:
	## [right, forward] of the player's frame, horizontal, following the controller's turn
	## about the vertical (same frame tilt() measures in). Use them to split the world-frame
	## gyro into pitch (gyro . right, + = nose up), roll (gyro . forward, + = right side down)
	## and yaw (gyro.y, + = turning left).
	var w := q * _up_body
	var swing := Quaternion(Vector3.UP, w) if w.y > -0.99 else Quaternion.IDENTITY
	var twist := swing.inverse() * (q * _neutral.inverse())
	var right := twist * _right0
	right.y = 0.0
	right = right.normalized()
	return [right, Vector3.UP.cross(right)]
