# ClipNote

A note app that watches your clipboard. Based on [CBNote](https://github.com/Cizzuk/CBNote) by Cizzuk, with background clipboard monitoring from [Clip](https://github.com/rileytestut/Clip) by Riley Testut.

## Clipboard monitoring

ClipNote keeps running in the background and posts a notification whenever the clipboard changes. Tapping the notification opens ClipNote and saves the clipboard as a new note.

- Background location updates (approximate, never stored) keep the app alive. Grant location access "Always".
- A private Pasteboard API delivers clipboard change events while the app is in the background, so this can't ship on the App Store.
- If iOS suspends or kills ClipNote, an "App Stopped Running" notification asks you to reopen it.
- To skip the paste prompt on every save, set Settings > ClipNote > Paste from Other Apps to Allow.

Turn monitoring off in ClipNote's settings under Clipboard Monitoring.

## CBNote features

- Launch from Camera Control, the Action Button, Control Center or Shortcuts into the in-app camera, a paste from the clipboard, a new note, an audio recording or a custom URL
- Notes are plain files on the device; many file formats are supported
- Copy a note to the clipboard with a swipe

## License

CBNote is licensed under the [MIT License](LICENSE). Clip is released into the public domain under the [Unlicense](https://github.com/rileytestut/Clip/blob/main/UNLICENSE).
