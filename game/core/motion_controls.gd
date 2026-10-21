class_name RSMotionControls
extends RefCounted
## One frame of motion-game input, filled by RSMotionGestures from a controller (or by a bot)
## and read by a rider: the skateboarder and the skier today, any board, ski or steer-and-jump
## game later.

var steer := 0.0           ## -1..1, + = tilt right
var pitch := 0.0           ## tilt back (nose up) in units of a full stick, can exceed 1
var yaw_delta := 0.0       ## rad the controller turned about the vertical this frame (+ = left)
var ollie := 0.0           ## > 0 this frame: an upward flick (jump / pop), strength 0..1
var flip := 0              ## -1 / +1 this frame: flick to the left / right
var push := false          ## B pressed this frame
var grab := false          ## B held
