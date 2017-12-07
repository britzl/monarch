[![Build Status](https://travis-ci.org/britzl/monarch.svg?branch=master)](https://travis-ci.org/britzl/monarch)

# Monarch
Monarch is a screen manager for the [Defold](https://www.defold.com) game engine.

# Installation
You can use Monarch in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

https://github.com/britzl/monarch/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/monarch/releases).

# Usage
Using Monarch requires that screens are created in a certain way. Once you have one or more screens created you can start navigating between the screens.

## Creating screens
Monarch screens are created in individual collections and loaded through collection proxies. The recommended setup is to create one game object per screen and per game object attach a collection proxy component and an instance of the ```screen.script``` provided by Monarch. The screen.script will take care of the setup of the screen. All you need to do is to make sure that the script properties on the ```screen.script``` are correct:

* **Screen Proxy (url)** - The URL to the collection proxy component containing the actual screen. Defaults to ```#collectionproxy```.
* **Screen Id (hash)** - A unique id that can be used to reference the screen when navigating your app.
* **Popup (boolean)** - Check this if the screen should be treated as a [popup](#popups).
* **Transition Url (url)** - Optional URL to call when the screen is about to be shown/hidden. Use this to trigger a transition (see the section on [transitions](#transitions)).
* **Focus Url (url)** - Optional URL to call when the screen gains or loses focus (see the section on [screen focus](#screen-focus-gainloss)).

![](docs/setup.png)

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
A screen that is flagged as a popup (see list of screen properties above) will be treated slightly differently when it comes to navigation. If a popup is at the top of the stack (ie currently shown) and another screen or popup is shown then the current popup will be removed from the stack. This means that it is not possible to have a popup anywhere in the stack but the top. This also means that you cannot navigate back to a popup since popups can only exist on the top of the stack. Another important difference between normal screens and popups is that when a popup is shown on top of a non-popup the current top screen will not be unloaded and instead remain visible in the background.

* Stack is ```[A, B]```
* A call to ```monarch.show(C)``` is made and C is a popup
* Stack is ```[A, B, C]```
* A call to ```monarch.show(D)```
* Stack is ```[A, B, D]```

## Transitions
You can add optional transitions when navigating between screens. The default behavior is that screen navigation is instant but if you have defined a transition for a screen Monarch will wait until the transition is completed before proceeding. The Transition Url property described above should be the URL to a script with an ```on_message``` handlers for the following messages:

* ```transition_show_in```
* ```transition_show_out```
* ```transition_back_in```
* ```transition_back_out```

When a transition is completed it is up to the developer to send a ```transition_done``` message back to the sender to indicate that the transition is completed and that Monarch can continue the navigation sequence.

Monarch comes with a system for setting up transitions easily in a gui_script using the ```monarch.transitions.gui``` module. Example:

	local transitions = require "monarch.transitions.gui"

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
	end

### Predefined transitions
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


## Screen focus gain/loss
Monarch will send focus gain and focus loss messages if a Focus Url was provided when the screen was created. The focus gained message will contain the id of the previous screen and the focus loss message will contain the id of the next screen. Example:

	local monarch = require "monarch.monarch"

	function on_message(self, message_id, message, sender)
		if message_id == monarch.FOCUS_GAINED then
			print("Focus gained, previous screen: ", message.id)
		elseif message_id == monarch.FOCUS_LOST then
			print("Focus lost, next screen: ", message.id)
		end
	end

## Callbacks
Both the ```monarch.show()``` and ```monarch.back()``` functions take an optional callback function that will be invoked when the ```transition_show_in``` (or the ```transition_back_in``` in the case of a ```monarch.back()``` call) transition is completed. The transition is considered completed when a ```transition_done``` message has been received (see section on [transitions](#transitions) above).

## Monarch API

### monarch.show(screen_id, [options], [data], [callback])
Show a Monarch screen

**PARAMETERS**
* ```screen_id``` (hash) - Id of the screen to show.
* ```options``` (table) - Options when showing the new screen (see below).
* ```data``` (table) - Optional data to associate with the screen.  Retrieve using ```monarch.data()```.
* ```callback``` (function) - Function to call when the new screen is visible.

The options table can contain the following fields:

* ```clear``` (boolean) - If the clear flag is set Monarch will search the stack for the screen that is to be shown. If the screen already exists in the stack and the clear flag is set Monarch will remove all screens between the current top and the screen in question.
* ```reload``` (boolean) - If the reload flag is set Monarch will reload the collection proxy if it's already loaded (this can happen if the previous screen was a popup).

### monarch.back([data], [callback])
Go back to a previous Monarch screen

**PARAMETERS**
* ```data``` (table) - Optional data to associate with the screen you are going back to.  Retrieve using ```monarch.data()```.
* ```callback``` (function) - Function to call when the previous screen is visible.


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
