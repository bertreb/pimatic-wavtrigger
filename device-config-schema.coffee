module.exports = {
  title: "pimatic-wavtrigger device config schemas"
  WavTrigger: {
    title: "WavTrigger config options"
    type: "object"
    extensions: ["xLink"]
    properties:
      port:
        description: "the usb port number the WavTrigger is connected on"
        type: "string"
      volume:
        description: "default volume (-90 till 0)"
        type: "number"
        default: -10
      buttons:
        description: "Tracks to trigger"
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          properties:
            id:
              description: "The track button id"
              type: "string"
            text:
              description: "The track button name"
              type: "string"
            wavNumber:
              description: "The wavTrigger file number"
              type: "number"
            confirm:
              description: "Ask the user to confirm the button press"
              type: "boolean"
              default: false
      enableActiveButton:
        description: "Highlight last pressed track if enabled"
        type: "boolean"
        default: true
  }
}
