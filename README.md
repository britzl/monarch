![](docs/logo.jpg)

[![Build Status](https://travis-ci.org/britzl/monarch.svg?branch=master)](https://travis-ci.org/britzl/monarch)
[![Code Coverage](https://codecov.io/gh/britzl/monarch/branch/master/graph/badge.svg)](https://codecov.io/gh/britzl/monarch)
[![Latest Release](https://img.shields.io/github/release/britzl/monarch.svg)](https://github.com/britzl/monarch/releases)

# Monarch
Monarch is a screen manager for the [Defold](https://www.defold.com) game engine.


# Installation
You can use Monarch in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

https://github.com/britzl/monarch/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/monarch/releases).


# Usage
Using Monarch requires that screens are created in a certain way. Once you have one or more screens created you can start navigating between the screens.


## Creating screens
Monarch screens are created in individual collections and either loaded through collection proxies or created through collection factories.

### Collection proxies
For proxies the recommended setup is to create one game object per screen and per game object attach a collection proxy component and an instance of the ```screen_proxy.script``` provided by Monarch. The ```screen_proxy.script``` will take care of the setup of the screen. All you need to do is to make sure that the script properties on the script are correct:

* **Screen Proxy (url)** - The URL to the collection proxy component containing the actual screen. Defaults to ```#collectionproxy```.
* **Screen Id (hash)** - A unique id that can be used to reference the screen when navigating your app.
* **Popup (boolean)** - Check this if the screen should be treated as a [popup](#popups).
* **Popup on Popup (boolean)** - Check this if the screen is a [popup](#popups) and it can be shown on top of other popups.
* **Timestep below Popup (number)** - Timestep to set on screen proxy when it is below a popup. This is useful when pausing animations and gameplay while a popup is open.
* **Transition Url (url)** - Optional URL to call when the screen is about to be shown/hidden. Use this to trigger a transition (see the section on [transitions](#transitions)).
* **Focus Url (url)** - Optional URL to call when the screen gains or loses focus (see the section on [screen focus](#screen-focus-gainloss)).

![](docs/setup_proxy.png)

### Collection factories
For factories the recommended setup is to create one game object per screen and per game object attach a collection factory component and an instance of the ```screen_factory.script``` provided by Monarch. The ```screen_factory.script``` will take care of the setup of the screen. All you need to do is to make sure that the script properties on the script are correct:

* **Screen Factory (url)** - The URL to the collection factory component containing the actual screen. Defaults to ```#collectionfactory```.
* **Screen Id (hash)** - A unique id that can be used to reference the screen when navigating your app.
* **Popup (boolean)** - Check this if the screen should be treated as a [popup](#popups).
* **Popup on Popup (boolean)** - Check this if the screen is a [popup](#popups) and it can be shown on top of other popups.
* **Transition Id (url)** - Optional id of the game object to send a message to when the screen is about to be shown/hidden. Use this to trigger a transition (see the section on [transitions](#transitions)).
* **Focus Id (url)** - Optional id of the game object to send a message to when the screen gains or loses focus (see the section on [screen focus](#screen-focus-gainloss)).

![](docs/setup_factory.png)

Note: Monarch supports dynamic collection factories (ie where the "Load Dynamically" checkbox is checked).

## Nesting screens
Sometimes it might be desirable to have a screen that contains one or more sub-screens or children, for instance popups that are used only by that screen. Monarch supports nested screens only when the parent screen is created via a collection factory. If the parent screen is loaded via a collection proxy the sub/child-screens won't be able to receive any input.

## Navigating between screens
The navigation in Monarch is based around a stack of screens. When a screen is shown it is pushed to the top of the stack. When going back to a previous screen the topmost screen on the stack is removed. Example:

* Showing screen A
* Stack is ```[A]```
* Showing screen B
* Stack is ```[A, B]``` - (B is on top)
* Going back
* Stack is ```[A]```

### Showing a new screen
You show a screen in one of two ways:

1. Post a ```show``` message to the ```screen.script```
2. Call ```monarch.show()``` (see below)

Showing a screen will push it to the top of the stack and trigger an optional transition. The previous screen will be hidden (with an optional transition) unless the screen to be shown is a [popup](#popups).

NOTE: You must ensure that the ```init()``` function of the ```screen.script``` has run. The ```init()``` function is responsible for registering the screen and it's not possible to show it until this has happened. A good practice is to delay the first call by posting a message to a controller script or similar before calling ```monarch.show()``` the first time:

	function init(self)
		msg.post("#", "show_first_screen")
	end

	function on_message(self, message_id, message, sender)
		monarch.show(hash("first_screen"))
	end

#### Preventing duplicates in the stack
You can pass an optional ```clear``` flag when showing a screen (either as a key value pair in the options table when calling ```monarch.show()``` or in the message). If the clear flag is set Monarch will search the stack for the screen in question. If the screen already exists in the stack and the ```clear``` flag is set Monarch will remove all screens between the current top and the screen in question. Example:

* Stack is ```[A, B, C, D]``` - (D is on top)
* A call to ```monarch.show(B, { clear = true })``` is made
* Stack is ```[A, B]```

As opposed to if the ```clear``` flag was not set:

* Stack is ```[A, B, C, D]``` - (D is on top)
* A call to ```monarch.show(B, { clear = false })``` is made
* Stack is ```[A, B, C, D, B]``` - (B is on top)

### Going back to a previous screen
You navigate back in the screen hierarchy in one of two ways:

1. Post a ```back``` message to the ```screen.script```
2. Call ```monarch.back()``` (see below)


## Input focus
Monarch will acquire and release input focus on the game objects containing the proxies to the screens and ensure that only the top-most screen will ever have input focus.

## Popups
A screen that is flagged as a popup (see [list of screen properties](#creating-screens) above) will be treated slightly differently when it comes to navigation.

### Popup on normal screen
If a popup is shown on top of a non-popup the current top screen will not be unloaded and instead remain visible in the background:

* Stack is ```[A, B]```
* A call to ```monarch.show(C)``` is made and C is a popup
* Stack is ```[A, B, C]``` and B will still be visible

### Popup on popup
If a popup is at the top of the stack and another popup is shown the behavior will depend on if the new popup has the Popup on Popup flag set or not. If the Popup on Popup flag is set the underlying popup will remain visible.

* Stack is ```[A, B, C]``` and C is a popup
* A call to ```monarch.show(D)``` is made and D is a popup with the popup on popup flag set
* Stack is ```[A, B, C, D]```

If the Popup on Popup flag is not set then the underlying popup will be closed, just as when showing a normal screen on top of a popup (see above).

* Stack is ```[A, B, C]``` and C is a popup
* A call to ```monarch.show(D)``` is made and D is a popup without the popup on popup flag set
* Stack is ```[A, B, D]```

### Screen on popup
If a screen is shown on top of one or more popups they will all be removed from the stack:

* Stack is ```[A, B, C, D]``` and C and D are popups
* A call to ```monarch.show(E)``` is made and E is not a popup
* Stack is ```[A, B, E]```


## Transitions
You can add optional transitions when navigating between screens. The default behavior is that screen navigation is instant but if you have defined a transition for a screen Monarch will wait until the transition is completed before proceeding. The Transition Url property described above should be the URL to a script with an ```on_message``` handlers for the following messages:

* ```transition_show_in``` (constant defined as ```monarch.TRANSITION.SHOW_IN```)
* ```transition_show_out``` (constant defined as ```monarch.TRANSITION.SHOW_OUT```)
* ```transition_back_in``` (constant defined as ```monarch.TRANSITION.BACK_IN```)
* ```transition_back_out``` (constant defined as ```monarch.TRANSITION.BACK_OUT```)

When a transition is completed it is up to the developer to send a ```transition_done``` (constant ```monarch.TRANSITION.DONE```) message back to the sender to indicate that the transition is completed and that Monarch can continue the navigation sequence.


### Predefined transitions
Monarch comes with a system for setting up transitions easily in a gui_script using the ```monarch.transitions.gui``` module. Example:

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

The predefined transitions provided by ```monarch.transitions.gui``` are:

* ```slide_in_right```
* ```slide_in_left```
* ```slide_in_top```
* ```slide_in_bottom```
* ```slide_out_right```
* ```slide_out_left```
* ```slide_out_top```
* ```slide_out_bottom```
* ```scale_in```
* ```scale_out```
* ```fade_in``` - Set node alpha to fully transparent (i.e. 0.0) and fade to fully opaque (i.e. 1.0)
* ```fade_out``` - Set node alpha to fully opaque (i.e. 1.0) and fade to fully transparent (i.e. 0.0)

Additionally there's functionality to create a full set of transitions for common transition styles:

* ```transitions.in_right_out_left(node, duration, [delay], [easing])```
* ```transitions.in_left_out_right(node, duration, [delay], [easing])```
* ```transitions.in_left_out_left(node, duration, [delay], [easing])```
* ```transitions.in_right_out_right(node, duration, [delay], [easing])```
* ```transitions.fade_in_out(node, duration, [delay], [easing])```

**PARAMETERS**
* ```node``` (node) - Gui node to animate.
* ```duration``` (number) - Transition duration in seconds.
* ```delay``` (number) - Transition delay in seconds.
* ```easing``` (table) - Easing table, created from a function provided by ```monarch.transitions.easings```

**RETURN**
* ```instance``` - The created transition instance


### Custom transitions
You can create and use your own transition as long as the provided transition function has the following function signature:

	custom_transition(node, to, easing, duration, delay, cb)

**PARAMETERS**
* ```node``` (node) - Gui node to animate.
* ```to``` (vector3) - Target position.
* ```easing``` (number) - One of gui.EASING_* constants.
* ```duration``` (number) - Transition duration in seconds.
* ```delay``` (number) - Transition delay in seconds.
* ```cb``` (function) - This function must be called when the transition is completed.


### Dynamic orientation and resized windows
When using dynamic screen orientation together with gui layouts or using transitions on a platform where the window can be resized it's important to make sure that the created transitions adapt to the change in orientation or window size. The transition system takes care of layout changes automatically, but when it comes to changes in window size you need to notify the transition manually:

	local transitions = require "monarch.transitions.gui"

	function init(self)
		self.transition = transitions.create(gui.get_node("root"))
	end

	function on_message(self, message_id, message, sender)
		if message_id == hash("my_resize_message") then
			self.transition.window_resized(message.width, message.height)
		end
	end


### Screen stack info and transitions
The transition message sent to the Transition Url specified in the screen configuration contains additional information about the transition. For the ```transition_show_in``` and ```transition_back_out``` messages the message contains the previous screen id:

	function on_message(self, message_id, message, sender)
		if message_id == hash("transition_show_in") or message_id == hash("transition_back_out") then
			print(message.previous_screen)
		end
	end

For the ```transition_show_out``` and ```transition_back_in``` messages the message contains the next screen id:

	function on_message(self, message_id, message, sender)
		if message_id == hash("transition_show_out") or message_id == hash("transition_back_in") then
			print(message.next_screen)
		end
	end

This information can be used to create dynamic transitions where the direction of the transition depends on the previous/next screen


## Screen focus gain/loss
Monarch will send focus gain and focus loss messages if a Focus Url was provided when the screen was created. The focus gained message will contain the id of the previous screen and the focus loss message will contain the id of the next screen. Example:

	local monarch = require "monarch.monarch"

	function on_message(self, message_id, message, sender)
		if message_id == monarch.FOCUS.GAINED then
			print("Focus gained, previous screen: ", message.id)
		elseif message_id == monarch.FOCUS.LOST then
			print("Focus lost, next screen: ", message.id)
		end
	end


## Callbacks
Both the ```monarch.show()``` and ```monarch.back()``` functions take an optional callback function that will be invoked when the ```transition_show_in``` (or the ```transition_back_in``` in the case of a ```monarch.back()``` call) transition is completed. The transition is considered completed when a ```transition_done``` message has been received (see section on [transitions](#transitions) above).


## Monarch API

### monarch.show(screen_id, [options], [data], [callback])
Show a Monarch screen. Note that the screen must be registered before it can be shown. The ```init()``` function of the ```screen.script``` takes care of registration.

**PARAMETERS**
* ```screen_id``` (hash) - Id of the screen to show.
* ```options``` (table) - Options when showing the new screen (see below).
* ```data``` (table) - Optional data to associate with the screen.  Retrieve using ```monarch.data()```.
* ```callback``` (function) - Optional function to call when the new screen is visible.

The options table can contain the following fields:

* ```clear``` (boolean) - If the clear flag is set Monarch will search the stack for the screen that is to be shown. If the screen already exists in the stack and the clear flag is set Monarch will remove all screens between the current top and the screen in question.
* ```reload``` (boolean) - If the reload flag is set Monarch will reload the collection proxy if it's already loaded (this can happen if the previous screen was a popup).

**RETURN**
* ```success``` (boolean) - True if the process of showing the screen was started successfully. False if already busy showing/hiding a screen.


### monarch.back([data], [callback])
Go back to a previous Monarch screen

**PARAMETERS**
* ```data``` (table) - Optional data to associate with the screen you are going back to.  Retrieve using ```monarch.data()```.
* ```callback``` (function) - Optional function to call when the previous screen is visible.

**RETURN**
* ```success``` (boolean) - True if the process of going back to a previous screen was started successfully. False if already busy showing/hiding a screen.


### monarch.preload(screen_id, [callback])
Preload a Monarch screen. This will load but not enable the screen. This is useful for content heavy screens that you wish to be able to show without having to wait for it load.

**PARAMETERS**
* ```screen_id``` (hash) - Id of the screen to preload.
* ```callback``` (function) - Optional function to call when the new screen is preloaded.


### monarch.top([offset])
Get the id of the screen at the top of the stack.

**PARAMETERS**
* ```offset``` (number) - Optional offset from the top of the stack, ie -1 to get the previous screen

**RETURN**
* ```screen_id``` (hash) - Id of the requested screen


### monarch.bottom([offset])
Get the id of the screen at the bottom of the stack.

**PARAMETERS**
* ```offset``` (number) - Optional offset from the bottom of the stack

**RETURN**
* ```screen_id``` (hash) - Id of the requested screen


### monarch.data(screen_id)
Get the data associated with a screen (from a call to ```monarch.show()``` or ```monarch.back()```).

**PARAMETERS**
* ```screen_id``` (hash) - Id of the screen to get data for

**RETURN**
* ```data``` (table) - Data associated with the screen.


### monarch.screen_exists(screen_id)
Check if a Monarch screen exists.

**PARAMETERS**
* ```screen_id``` (hash) - Id of the screen to get data for

**RETURN**
* ```exists``` (boolean) - True if the screen exists.


### monarch.is_busy()
Check if Monarch is busy showing and/or hiding a screen.

**RETURN**
* ```busy``` (boolean) - True if busy hiding and/or showing a screen.


### monarch.add_listener([url])
Add a URL that will be notified of navigation events.

**PARAMETERS**
* ```url``` (url) - URL to send navigation events to. Will use current URL if omitted.


### monarch.remove_listener([url])
Remove a previously added listener.

**PARAMETERS**
* ```url``` (url) - URL to remove. Will use current URL if omitted.


### monarch.debug()
Enable verbose logging of the internals of Monarch.


### monarch.SCREEN_TRANSITION_IN_STARTED
Message sent to listeners when a screen has started to transition in.

**PARAMETERS**
* ```screen``` (hash) - Id of the screen
* ```previous_screen``` (hash) - Id of the previous screen (if any)


### monarch.SCREEN_TRANSITION_IN_FINISHED
Message sent to listeners when a screen has finished to transition in.

**PARAMETERS**
* ```screen``` (hash) - Id of the screen
* ```previous_screen``` (hash) - Id of the previous screen (if any)


### monarch.SCREEN_TRANSITION_OUT_STARTED
Message sent to listeners when a screen has started to transition out.

**PARAMETERS**
* ```screen``` (hash) - Id of the screen
* ```next_screen``` (hash) - Id of the next screen (if any)


### monarch.SCREEN_TRANSITION_OUT_FINISHED
Message sent to listeners when a screen has finished to transition out.

**PARAMETERS**
* ```screen``` (hash) - Id of the screen
* ```next_screen``` (hash) - Id of the next screen (if any)
