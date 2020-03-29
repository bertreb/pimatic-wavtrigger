module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = require('lodash')
  SerialPort = require('serialport')
  M = env.matcher

  class WavTriggerPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-wavtrigger-config-schema'
      @configProperties = pluginConfigDef.properties

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass('WavTrigger', {
        configDef: deviceConfigDef.WavTrigger,
        createCallback: (config, lastState) => new WavTrigger(config, lastState, @framework)
      })

      @framework.ruleManager.addActionProvider(new WavTriggerActionProvider(@framework))


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
      @serialport = @config.port
      @volume = @config.volume
      @wavOnline = false

      @buttons = @config.buttons

      @_lastPressedButton = lastState?.button?.value
      for button in @config.buttons
        @_button = button if button.id is @_lastPressedButton

      #
      # init WavTrigger
      #
      @port = new SerialPort( @serialport, { autoOpen: false, baudRate: 57600 })
      @wtStart()
      @wtDefaultVolume = @defaultVolume
      @wtVolume(@wtDefaultVolume)

      @port.on 'error', (err) =>
        env.logger.debug "Serialport error handled " + err
        @status = "closed"
        @wavOnline = false

      @port.on 'open', () =>
        env.logger.debug "Serialport connected"
        @status = "open"
        @wavOnline = true

      @port.on 'close', () =>
        env.logger.debug "Serialport closed"
        @status = "closed"
        @wavOnline = false

      @on 'button', (buttonId)=>
        button = _.find(@buttons, (b)=> (b.id).indexOf(buttonId)>=0)
        if button?
          @wtSolo(button.wavNumber)
          env.logger.info "WavTrigger track '#{button.wavNumber}' played"
        else
          env.logger.debug "Unknown track number #{button}"
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
          env.logger.debug 'Error opening port: ' + err.message
          return
        @wavOnline = true
        env.logger.debug "Port is opened"
        #@wtPower(true)
        # play startup tune
        #@wtSolo(99)
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


    execute: (command, params) =>
      return new Promise((resolve, reject) =>
        env.logger.debug "Execute WavTrigger '#{@id}', command: " + command + ', params: ' + JSON.stringify(params,null,2)
        switch command
          when "track"
            @wtSolo(params.tracknumber)
            resolve()
          when "stop"
            @wtStop()
            resolve()
          else
            reject()
      )

    destroy:() =>
      @removeAllListeners()
      @wtStop()
      if @port?
        @port.close()
      super()

  class WavTriggerActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>
      wavDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class is "WavTrigger").value()
      wavDevice = null
      match = null
      @command = ""
      @params = {}

      setCommand = (command) =>
        @command = command

      setTrackNumber = (m, tokens) =>
        if tokens < 0
          context?.addError("Minimum track number is 0")
          return
        if tokens > 999
          context?.addError("Maximum track number is 999")
          return
        @params["tracknumber"] = tokens
        setCommand("track")
        match = m.getFullMatch()
        return

      setTrackVar = (m, tokens) =>
        @params["trackvar"] = tokens
        setCommand("track")
        match = m.getFullMatch()
        return

      m = M(input, context)
        .match('wav ')
        .matchDevice(wavDevices, (m, d) =>
          # Already had a match with another device?
          if wavDevice? and wavDevice.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          wavDevice = d
        )
        .or([
          ((m) =>
            return m.match(' stop', (m) =>
              setCommand("stop")
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' play ')
              .or([
                ((m) =>
                  return m.matchVariable(setTrackVar)
                ),
                ((m) =>
                  return m.matchNumber(setTrackNumber)
                )
              ])
          )
        ])

      match = m.getFullMatch()

      if m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new WavTriggerActionHandler(@framework, wavDevice, @command, @params)
        }
      else
        return null


  class WavTriggerActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @wavDevice, @command, @params) ->

    executeAction: (simulate) =>
      if simulate
        return __("would execute command \"%s\"", @command)
      else
        unless @wavDevice.wavOnline
          return __("Rule not executed, WavTrigger is offline")
        _params = @params
        if @command is "track"
          if _params.trackvar?
            _var = (_params.trackvar).slice(1) if (_params.trackvar).indexOf('$') >= 0
            _trackNumber = Number @framework.variableManager.getVariableValue(_var)
            unless _tracknumber?
              return __("\"%s\" Track number variable does not excist ")
          else if _params.tracknumber?
            _trackNumber = Number _params.tracknumber
          else
            return __("\"%s\" track number is missing")
          if _trackNumber < 0 or _trackNumber > 999
              return __("\"%s\" Rule not executed WavTrigger offline")
          _params.tracknumber = _trackNumber
          @wavDevice.execute(@command, _params)
          .then(()=>
            return __("\"%s\" Executed WavTrigger command ", @command)
          ).catch((err)=>
            env.logger.debug "Error in WavTrigger execute " + err
            return __("\"%s\" Rule not executed WavTrigger offline") + err
          )
        else
          @wavDevice.execute(@command, _params)
          .then(()=>
            return __("\"%s\"Executed WavTrigger command ", @command)
          ).catch((err)=>
            env.logger.debug "Error in WavTrigger execute " + err
            return __("\"%s\" Rule not executed WavTrigger offline") + err
          )


  wavTriggerPlugin = new WavTriggerPlugin
  return wavTriggerPlugin
