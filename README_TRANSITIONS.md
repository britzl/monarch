# Transitions
You can add optional transitions when navigating between screens. The default behavior is that screen navigation is instant but if you have defined a transition for a screen Monarch will wait until the transition is completed before proceeding. The `Transition Url` (proxy) or `Transition Id` (collectionfactory) property described above should be the URL/Id to a script with an `on_message` handlers for the following messages:

* `transition_show_in` (constant defined as `monarch.TRANSITION.SHOW_IN`)
* `transition_show_out` (constant defined as `monarch.TRANSITION.SHOW_OUT`)
* `transition_back_in` (constant defined as `monarch.TRANSITION.BACK_IN`)
* `transition_back_out` (constant defined as `monarch.TRANSITION.BACK_OUT`)

When a transition is completed it is up to the developer to send a `transition_done` (constant `monarch.TRANSITION.DONE`) message back to the sender to indicate that the transition is completed and that Monarch can continue the navigation sequence.


## Predefined transitions
Monarch comes with a system for setting up transitions easily in a gui_script using the `monarch.transitions.gui` module. Example:

```lua
local transitions = require "monarch.transitions.gui"
local monarch = require "monarch.monarch"

function init(self)
	-- create transitions for the node 'root'
	-- the node will slide in/out from left and right with
	-- a specific easing, duration and delay
	self.transition = transitions.create(gui.get_node("root"))
		.show_in(transitions.slide_in_right, gui.EASING_OUTQUAD, 0.6, 0)
		.show_out(transitions.slide_out_left, gui.EASING_INQUAD, 0.6, 0)
		.back_in(transitions.slide_in_left, gui.EASING_OUTQUAD, 0.6, 0)
		.back_out(transitions.slide_out_right, gui.EASING_INQUAD, 0.6, 0)
end

function on_message(self, message_id, message, sender)
	self.transition.handle(message_id, message, sender)
	-- you can also check when a transition has completed:
	if message_id == monarch.TRANSITION.DONE and message.transition == monarch.TRANSITION.SHOW_IN then
		print("Show in done!")
	end
end
```

It is also possible to assign transitions to multiple nodes:

```lua
function init(self)
	self.transition = transitions.create() -- note that no node is passed to transition.create()!
		.show_in(gui.get_node("node1"), transitions.slide_in_right, gui.EASING_OUTQUAD, 0.6, 0)
		.show_in(gui.get_node("node2"), transitions.slide_in_right, gui.EASING_OUTQUAD, 0.6, 0)
end
```

The predefined transitions provided by `monarch.transitions.gui` are:

* `slide_in_right`
* `slide_in_left`
* `slide_in_top`
* `slide_in_bottom`
* `slide_out_right`
* `slide_out_left`
* `slide_out_top`
* `slide_out_bottom`
* `scale_in`
* `scale_out`
* `fade_in` - Set node alpha to fully transparent (i.e. 0.0) and fade to fully opaque (i.e. 1.0)
* `fade_out` - Set node alpha to fully opaque (i.e. 1.0) and fade to fully transparent (i.e. 0.0)

Additionally there's functionality to create a full set of transitions for common transition styles:

* `transitions.in_right_out_left(node, duration, [delay], [easing])`
* `transitions.in_left_out_right(node, duration, [delay], [easing])`
* `transitions.in_left_out_left(node, duration, [delay], [easing])`
* `transitions.in_right_out_right(node, duration, [delay], [easing])`
* `transitions.fade_in_out(node, duration, [delay], [easing])`

**PARAMETERS**
* `node` (node) - Gui node to animate.
* `duration` (number) - Transition duration in seconds.
* `delay` (number) - Transition delay in seconds.
* `easing` (table) - Easing table, created from a function provided by `monarch.transitions.easings`

**RETURN**
* `instance` - The created transition instance


## Custom transitions
You can create and use your own transition as long as the provided transition function has the following function signature:

	custom_transition(node, to, easing, duration, delay, cb)

**PARAMETERS**
* `node` (node) - Gui node to animate.
* `to` (vector3) - Target position.
* `easing` (number) - One of gui.EASING_* constants.
* `duration` (number) - Transition duration in seconds.
* `delay` (number) - Transition delay in seconds.
* `cb` (function) - This function must be called when the transition is completed.


## Dynamic orientation and resized windows
When using dynamic screen orientation together with gui layouts or using transitions on a platform where the window can be resized it's important to make sure that the created transitions adapt to the change in orientation or window size. The transition system takes care of layout changes automatically, but when it comes to changes in window size you need to notify the transition manually:

```lua
local transitions = require "monarch.transitions.gui"

function init(self)
	self.transition = transitions.create(gui.get_node("root"))
end

function on_message(self, message_id, message, sender)
	if message_id == hash("my_resize_message") then
		self.transition.window_resized(message.width, message.height)
	end
end
```

## Screen stack info and transitions
The transition message sent to the Transition Url specified in the screen configuration contains additional information about the transition. For the `transition_show_in` and `transition_back_out` messages the message contains the previous screen id:

```lua
function on_message(self, message_id, message, sender)
	if message_id == hash("transition_show_in") or message_id == hash("transition_back_out") then
		print(message.previous_screen)
	end
end
```

For the `transition_show_out` and `transition_back_in` messages the message contains the next screen id:

```lua
function on_message(self, message_id, message, sender)
	if message_id == hash("transition_show_out") or message_id == hash("transition_back_in") then
		print(message.next_screen)
	end
end
```

This information can be used to create dynamic transitions where the direction of the transition depends on the previous/next screen.
