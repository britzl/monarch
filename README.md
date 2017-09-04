# Monarch
Monarch is a screen manager for the [Defold](https://www.defold.com) game engine.

# Installation
You can use Monarch in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the dependencies field under project add:

https://github.com/britzl/monarch/archive/master.zip

# Usage
Using Monarch requires that screens are created in a certain way. Ones you have one or more screens created you can start navigating between the screens.

## Creating screens
Monarch screens are created in individual collections and loaded through collection proxies. The recommended setup is to create one game objects per screen and per game object attach a collection proxy component and an instance of the ````screen.script```` provided by Monarch. The screen.script will take care of the setup of the screen. All you need to do is to make sure that the script properties on the screen.script are correct:

* **Screen Proxy (url)** - The URL to the collection proxy component containing the actual screen. Defaults to #collectionproxy
* **Screen Id (hash)** - A unique id that can be used to reference the screen when navigating your app
* **Popup (boolean)** - Check this if the screen should be treated as a popup (see the section on popups below)
* **Transition Show In (url)** - Optional URL to call when the screen is about to be shown. Use this to trigger a transition (see the section on transitions below)
* **Transition Show Out (url)** - Optional URL to call when the screen is about to be hidden. Use this to trigger a transition (see the section on transitions below)
* **Transition Back In (url)** - Optional URL to call when the screen is about to be shown when navigating back in the screen hierarchy. Use this to trigger a transition (see the section on transitions below)
* **Transition Back Out (url)** - Optional URL to call when the screen is about to be hidden when navigating back in the screen hierarchy. Use this to trigger a transition (see the section on transitions below)


## Navigating between screens
The navigation in Monarch is based around a stack of screens. When a screen is shown it is pushed to the top of the stack. When going back to a previous screen the topmost screen on the stack is removed. Example:

* Showing screen A
* Stack is A
* Showing screen B
* Stack is A, B - (B is on top)
* Going back
* Stack is A

### Showing a new screen
You show a screen in one of two ways:

1. Post a ````show```` message to the screen.script
2. Call ````monarch.show(screen_id, [clear])````

Showing a screen will push it to the top of the stack and trigger an optional transition. The previous screen will be hidden (with an optional transition) unless the screen to be shown is a popup (see below).

#### Preventing duplicates in the stack
You can pass an optional clear flag when showing a screen (either as a second argument to ````monarch.show()```` or in the message). If the clear flag is set Monarch will look search the stack for the screen in question. If the screen already exists in the stack and the clear flag is set Monarch will remove all screens between the current top and the screen in question. Example:

* Stack is A, B, C, D - (D is on top)
* A call to ````monarch.show(B, true)```` is made
* Stack is A, B

### Going back to a previous screen
You navigate back in the screen hierarchy in one of two ways:

1. Post a ````back```` message to the ````screen.script````
2. Call ````monarch.back()````


## Input focus
Monarch will acquire and release input focus on the screen and ensure that only the top-most screen will ever have input focus.

## Popups
A screen that is flagged as a popup (see list of screen properties above) will be treated slightly differently when it comes to navigation. If a popup is at the top of the stack (ie currently shown) and another screen or popup is shown then the current popup will be removed from the stack. This means that it is not possible to a popup anywhere in the stack but the top. This also means that you cannot navigate back to a popup since popups can only exist on the top of the stack. Another important difference between normal screens and popups is that when a popup is shown on top of a non-popup the current top screen will not be unloaded.

## Transitions
You can add optional transitions when navigating between screens. The default behavior is that screen navigation is instant but if you have defined a transition for a screen Monarch will wait until the transition is completed before proceeding. The Transition Show In/Out and Transition Back In/Out properties described above should be URLs to one or more scripts with on_message handlers for the following messages:

* transition_show_in
* transition_show_out
* transition_back_in
* transition_back_out

When a transition is completed it is up to the developer to send a ````transition_done```` message back to the sender to indicate that the transition is completed and that Monarch can continue the navigation sequence. Example:

	function on_message(self, message_id, message, sender)
		if message_id == hash("transition_show_in") then
			-- slide in from the right
			gui.set_position(self.root, self.initial_position + vmath.vector3(1000, 0, 0))
			gui.animate(self.root, gui.PROP_POSITION, self.initial_position, go.EASING_INOUTQUAD, 0.6, 0, function()
				msg.post(sender, "transition_done")
			end)
		elseif message_id == hash("transition_show_out") then
			-- slide out to the left
			gui.animate(self.root, gui.PROP_POSITION, self.initial_position - vmath.vector3(1000, 0, 0), go.EASING_INOUTQUAD, 0.6, 0, function()
				msg.post(sender, "transition_done")
			end)
		end
		elseif message_id == hash("transition_back_in") then
			-- slide in from the left
			gui.set_position(self.root, self.initial_position - vmath.vector3(1000, 0, 0))
			gui.animate(self.root, gui.PROP_POSITION, self.initial_position, go.EASING_INOUTQUAD, 0.6, 0, function()
				msg.post(sender, "transition_done")
			end)
		end
		elseif message_id == hash("transition_back_out") then
			-- slide out to the right
			gui.animate(self.root, gui.PROP_POSITION, self.initial_position + vmath.vector3(1000, 0, 0), go.EASING_INOUTQUAD, 0.6, 0, function()
				msg.post(sender, "transition_done")
			end)
		end
	end
