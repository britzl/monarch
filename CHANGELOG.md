## Monarch 2.8.0 [britzl released 2018-06-10]
NEW: Prevent show/hide operations while busy showing/hiding another screen  
FIX: Make sure to properly finish active transitions when layout changes

## Monarch 2.7.0 [britzl released 2018-06-04]
NEW: Added monarch.top([offset]) and monarch.bottom([offset]) to get screen id of top and bottom screens (w. optional offset)  
NEW: Transition messages now contain `next_screen` or `previous_screen`

## Monarch 2.6.1 [britzl released 2018-06-04]
FIX: Check if screen has already been preloaded before trying to preload it again (the callback will still be invoked).

## Monarch 2.6.0 [britzl released 2018-06-03]
NEW: monarch.preload() to load but not show a screen. Useful for content heavy screens that you wish to show without delay.

## Monarch 2.5.0 [britzl released 2018-06-01]
NEW: Transitions will send a `transition_done` message to the creator of the transition to notify that the transition has finished. The `message` will contain which transition that was finished.

## Monarch 2.4.0 [britzl released 2018-05-26]
NEW: Screen transitions are remembered so that they can be replayed when the screen layout changes.

## Monarch 2.3.0 [britzl released 2018-03-24]
CHANGE: The functions in monarch.lua that previously only accepted a hash as screen id now also accepts strings (and does the conversion internally)

## Monarch 2.2.0 [britzl released 2018-03-19]
NEW: Transitions now handle layout changes (via `layout_changed` message)  
NEW: Transitions can now be notified of changes in window size using transition.window_resize(width, height)

## Monarch 2.1 [britzl released 2017-12-27]
NEW: Added Popup on Popup flag that allows a popup to be shown on top of another popup

## Monarch 2.0 [britzl released 2017-12-08]
BREAKING CHANGE: If you are using custom screen transitions (ie your own transition functions) you need to make a change to the function. The previous function signature was ```(node, to, easing, duration, delay, url)``` where ```url``` was the URL  to where the ```transition_done``` message was supposed to be posted. The new function signature for a transition function is: ```(node, to, easing, duration, delay, cb)``` where ```cb``` is a function that should be invoked when the transition is completed.  
  
FIX: Fixed issues related to screen transitions.  
FIX: Code cleanup to reduce code duplication.  
FIX: Improved documentation regarding transitions.

## Monarch 1.4 [britzl released 2017-12-06]
FIX: Several bugfixes for specific corner cases.

## Monarch 1.3 [britzl released 2017-12-01]
FIX: monarch.back(data, cb) set the data on the previous screen not the new current screen.  
NEW: monarch.is_top(id)  
NEW: monarch.get_stack()  
NEW: monarch.in_stack(id)

## Monarch 1.2 [britzl released 2017-11-28]
NEW: Message id constants exposed from the Monarch module  
NEW: Focus lost/gained contains id of next/previous screen

## Monarch 1.1 [britzl released 2017-11-22]
FIX: Bugfixes for transitions and state under certain circumstances  
NEW: Added 'reload' option to show() command.

## Monarch 1.0 [britzl released 2017-09-28]
First public stable release

## Monarch 0.9 [britzl released 2017-09-17]


