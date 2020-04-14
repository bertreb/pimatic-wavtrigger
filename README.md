# pimatic-wavtrigger
Pimatic plugin for controlling a Robert Sonics WavTrigger.

The WavTrigger plays high quality stereo audio tracks. The sd-card can contain 1000 wav audiotrack.
The WAV Trigger is polyphonic; it can play and blend up to 14 tracks at a time.

After installing the plugin, you create a WavTigger device with the following config:

```
port: "the usb port number the WavTrigger is connected on"
volume: "the default volume (-90 till 0)"
buttons: [
  button:
    id: "The track button id"
    text: "The track button name"
    wavNumber: "The wavTrigger file number (0-999)"
    confirm: "Ask the user to confirm the button press"
]
```
You can create a button to trigger a track, but it's not needed because the WavTrigger can be controlled via rules only.

Tracks can be started and stopped via rules. The syntax is:
```
wav <wav-device-id> [stop | play [tracknummber | $tracknumber-variable] ]
```
