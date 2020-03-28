module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = require('lodash')
  SerialPort = require('serialport')

  class WavTriggerPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-wavtrigger-config-schema'
      @configProperties = pluginConfigDef.properties

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass('WavTrigger', {
        configDef: deviceConfigDef.WavTrigger,
        createCallback: (config, lastState) => new WavTrigger(config, lastState, @framework)
      })

  class WavTrigger extends env.devices.Device

    attributes:
      button:
        description: "The last pressed button"
        type: "string"

    actions:
      buttonPressed:
        params:
          buttonId:
            type: "string"
        description: "Press a button"

    template: "buttons"

    _lastPressedButton: null

    constructor: (@config, lastState, @framework)->
      @id = @config.id
      @name = @config.name

      @buttons = @config.buttons

      @_lastPressedButton = lastState?.button?.value
      for button in @config.buttons
        @_button = button if button.id is @_lastPressedButton

      #
      # init WavTrigger
      #
      @port = new SerialPort('/dev/ttyS0', { autoOpen: false, baudRate: 57600 })
      @wtStart()
      @wtDefaultVolume = -10
      @wtVolume(@wtDefaultVolume)

      @on 'button', (buttonId)=>
        button = _.find(@buttons, (b)=> (b.id).indexOf(buttonId)>=0)
        if button?
          @wtSolo(button.wavNumber)
          env.logger.info "WavTrigger track '#{button.wavNumber}' played"
        else
          env.logger.debug "Unknown track number #{button.wavNumber}"
      super()

    getButton: -> Promise.resolve(@_lastPressedButton)

    buttonPressed: (buttonId) ->
      for b in @config.buttons
        if b.id is buttonId
          @_lastPressedButton = b.id
          @emit 'button', b.id
          return Promise.resolve()
      throw new Error("No button with the id #{buttonId} found")

    wtStart: () =>
      _WT_GET_VERSION = [0xF0,0xAA,0x05,0x01,0x55]
      @port.open((err) =>
        if err
          @logger.info('Error opening port: ', err.message)
          return
        @wtPower(true)
        # play startup tune
        @wtSolo(99)
      )

    wtPower: (_state) =>
      _WT_AMP_POWER = [0xF0,0xAA,0x06,0x09,0x00,0x55]
      if _state
        _WT_AMP_POWER[4] = 0x01
        @port.write(Buffer.from(_WT_AMP_POWER))
      else
        @port.write(Buffer.from(_WT_AMP_POWER))

    wtVolume: (_volume) =>
      _WT_VOLUME = [0xF0,0xAA,0x07,0x05,0x00,0x00,0x55]
      if _volume < -70 then _volume = -70
      if _volume > 4 then _volume = 4
      _WT_VOLUME[4] = _volume & 0xFF
      _WT_VOLUME[5] = (_volume & 0xFF00) >> 8
      @port.write(Buffer.from(_WT_VOLUME))

    wtSolo: (_track) =>
      _WT_TRACK_SOLO = [0xF0,0xAA,0x08,0x03,0x00,0x00,0x00,0x55]
      _WT_TRACK_SOLO[5] = _track & 0xFF
      _WT_TRACK_SOLO[6] = (_track & 0xFF00) >> 8
      @port.write(Buffer.from(_WT_TRACK_SOLO))

    wtFade: (_track) =>
      _WT_FADE = [0xF0,0xAA,0x0C,0x0A,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x55]
      _volume = 0
      _time = 10000
      _WT_FADE[4] = _track & 0xFF
      _WT_FADE[5] = (_track & 0xFF00) >> 8
      _WT_FADE[6] = _volume & 0xFF
      _WT_FADE[7] = (_volume & 0xFF00) >> 8
      _WT_FADE[8] = _time & 0xFF
      _WT_FADE[9] = (_time & 0xFF00) >> 8
      #_WT_FADE[10] = 0x00
      @port.write(Buffer.from(_WT_FADE))

    wtStop: () =>
      _WT_STOP_ALL = [0xF0,0xAA,0x05,0x04,0x55]
      #_WT_TRACK_STOP = [0xF0,0xAA,0x08,0x03,0x04,0x00,0x00,0x55]
      #_WT_TRACK_STOP[5] = _track & 0xFF
      #_WT_TRACK_STOP[6] = (_track & 0xFF00) >> 8
      @port.write(Buffer.from(_WT_STOP_ALL))

    destroy:() =>
      @removeAllListeners()
      @wtStop()
      if @port?
        @port.close()
      super()

  wavTriggerPlugin = new WavTriggerPlugin
  return wavTriggerPlugin

