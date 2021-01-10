
# Monarch API

## monarch.show(screen_id, [options], [data], [callback])
Show a Monarch screen. Note that the screen must be registered before it can be shown. The `init()` function of the screen script (either `screen_proxy.script` or `screen_factory.script`) takes care of registration. This operation will be added to the queue if Monarch is busy.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to show.
* `options` (table) - Options when showing the new screen (see below).
* `data` (table) - Optional data to associate with the screen.  Retrieve using `monarch.data()`.
* `callback` (function) - Optional function to call when the new screen is visible.

The options table can contain the following fields:

* `clear` (boolean) - If the `clear` flag is set Monarch will search the stack for the screen that is to be shown. If the screen already exists in the stack and the clear flag is set Monarch will remove all screens between the current top and the screen in question.
* `reload` (boolean) - If the `reload` flag is set Monarch will reload the collection proxy if it's already loaded (this can happen if the previous screen was a popup).
* `no_stack` (boolean) - If the `no_stack` flag is set Monarch will load the screen without adding it to the screen stack.
* `sequential` (boolean) - If the `sequential` flag is set Monarch will start loading the screen only after the previous screen finished transitioning out.
* `pop` (number) - If `pop` is set to a number, Monarch will pop that number of screens from the stack before adding the new one.

## monarch.replace(screen_id, [options], [data], [callback])
Replace the top of the stack with a new screen. Equivalent to calling `monarch.show()` with `pop = 1`. It takes the same parameters as `monarch.show()`.


## monarch.hide(screen_id, [callback])
Hide a screen that has been shown using the `no_stack` option. If used on a screen that was shown without the `no_stack` option it will only hide it if the screen is on top of the stack and the behavior will be exactly like if `monarch.back()` had been called. This operation will be added to the queue if Monarch is busy.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to hide.
* `callback` (function) - Optional function to call when the screen has been hidden.

**RETURN**
* `success` (boolean) - True if the process of hiding the screen was started successfully.


## monarch.back([data], [callback])
Go back to a previous Monarch screen. This operation will be added to the queue if Monarch is busy.

**PARAMETERS**
* `data` (table) - Optional data to associate with the screen you are going back to.  Retrieve using `monarch.data()`.
* `callback` (function) - Optional function to call when the previous screen is visible.


## monarch.preload(screen_id, [callback])
Preload a Monarch screen. This will load but not enable the screen. This is useful for content heavy screens that you wish to be able to show without having to wait for it load. This operation will be added to the queue if Monarch is busy.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to preload.
* `callback` (function) - Optional function to call when the screen is preloaded.


## monarch.is_preloading(screen_id)
Check if a Monarch screen is preloading (via monarch.preload() or the Preload screen setting).

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to check

**RETURN**
* `preloading` (boolean) - True if the screen is preloading.


## monarch.when_preloaded(screen_id, callback)
Invoke a callback when a screen has been preloaded.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to check
* `callback` (function) - Function to call when the screen has been preloaded.


## monarch.unload(screen_id, [callback])
Unload a preloaded Monarch screen. A preloaded screen will automatically get unloaded when hidden, but this function can be useful if a screen has been preloaded and it needs to be unloaded again without actually hiding it. This operation will be added to the queue if Monarch is busy.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to unload.
* `callback` (function) - Optional function to call when the screen is unloaded.


## monarch.top([offset])
Get the id of the screen at the top of the stack.

**PARAMETERS**
* `offset` (number) - Optional offset from the top of the stack, ie -1 to get the previous screen

**RETURN**
* `screen_id` (string|hash) - Id of the requested screen


## monarch.bottom([offset])
Get the id of the screen at the bottom of the stack.

**PARAMETERS**
* `offset` (number) - Optional offset from the bottom of the stack

**RETURN**
* `screen_id` (string|hash) - Id of the requested screen


## monarch.data(screen_id)
Get the data associated with a screen (from a call to `monarch.show()` or `monarch.back()`).

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to get data for

**RETURN**
* `data` (table) - Data associated with the screen.


## monarch.screen_exists(screen_id)
Check if a Monarch screen exists.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to get data for

**RETURN**
* `exists` (boolean) - True if the screen exists.


## monarch.is_busy()
Check if Monarch is busy showing and/or hiding a screen.

**RETURN**
* `busy` (boolean) - True if busy hiding and/or showing a screen.


## monarch.is_top(screen_id)
Check if a Monarch screen is at the top of the view stack.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to check

**RETURN**
* `exists` (boolean) - True if the screen is at the top of the stack.


## monarch.is_visible(screen_id)
Check if a Monarch screen is visible.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to check

**RETURN**
* `exists` (boolean) - True if the screen is visible.


## monarch.add_listener([url])
Add a URL that will be notified of navigation events.

**PARAMETERS**
* `url` (url) - URL to send navigation events to. Will use current URL if omitted.


## monarch.remove_listener([url])
Remove a previously added listener.

**PARAMETERS**
* `url` (url) - URL to remove. Will use current URL if omitted.


## monarch.post(screen_id, message_id, [message])
Post a message to a visible screen. If the screen is created through a collection proxy it must have specified a receiver url. If the screen is created through a collection factory the function will post the message to all game objects within the collection.

**PARAMETERS**
* `screen_id` (string|hash) - Id of the screen to post message to
* `message_id` (string|hash) - Id of the message to send
* `message` (table|nil) - Optional message data to send

**RETURN**
* `result` (boolean) - True if the message was sent
* `error` (string|nil) - Error message if unable to send message


## monarch.debug()
Enable verbose logging of the internals of Monarch.


## monarch.SCREEN_TRANSITION_IN_STARTED
Message sent to listeners added using `monarch.add_listener()` when a screen has started to transition in.

**PARAMETERS**
* `screen` (hash) - Id of the screen
* `previous_screen` (hash) - Id of the previous screen (if any)


## monarch.SCREEN_TRANSITION_IN_FINISHED
Message sent to listeners added using `monarch.add_listener()` when a screen has finished to transition in.

**PARAMETERS**
* `screen` (hash) - Id of the screen
* `previous_screen` (hash) - Id of the previous screen (if any)


## monarch.SCREEN_TRANSITION_OUT_STARTED
Message sent to listeners added using `monarch.add_listener()` when a screen has started to transition out.

**PARAMETERS**
* `screen` (hash) - Id of the screen
* `next_screen` (hash) - Id of the next screen (if any)


## monarch.SCREEN_TRANSITION_OUT_FINISHED
Message sent to listeners added using `monarch.add_listener()` when a screen has finished to transition out.

**PARAMETERS**
* `screen` (hash) - Id of the screen
* `next_screen` (hash) - Id of the next screen (if any)
