classdef DaqController < handle
  %HW.DAQCONTROLLER Summary of this class goes here
  %   Detailed explanation goes here
  
  properties
    ChannelNames = {} % name to refer to each channel
    %Signal generator for each channel. Each should be an object of class
    %hw.ControlSignalGenerator, for generating command waveforms.
    SignalGenerators = hw.PulseSwitcher.empty
    DaqIds = 'Dev1' % device ID's for each channel, e.g. 'Dev1'
    DaqChannelIds = {} % DAQ's ID for each channel, e.g. 'ao0'
  end
  
  properties (Transient)
    DaqSession % should be a DAQ session containing only analogue output channels
    DigitalDaqSession % a DAQ session containing only digital output channels
  end
  
  properties (Dependent)
    Value %The current voltage on each DAQ channel
    NumChannels %Number of channels controlled
    AnalogueChannelsIdx %Logical array of analogue channel IDs
  end
  
  properties (Access = private, Transient)
    CurrValue
  end
  
  methods
    function createDaqChannels(obj)
      if isempty(obj.DaqSession)
        obj.DaqSession = daq.createSession('ni');
      end
      if isempty(obj.DigitalDaqSession)&&any(~obj.AnalogueChannelsIdx)
        obj.DigitalDaqSession = daq.createSession('ni');
      end
      n = obj.NumChannels;
      if n > 0
        for ii = 1:n
          if iscell(obj.DaqIds)
            daqid = obj.DaqIds{ii};
          else
            daqid = obj.DaqIds;
          end
          if obj.AnalogueChannelsIdx(ii) % is channal analogue?
            obj.DaqSession.addAnalogOutputChannel(...
              daqid, obj.DaqChannelIds{ii}, 'Voltage');
          else % assume digital, always output only
            obj.DigitalDaqSession.addDigitalChannel(...
              daqid, obj.DaqChannelIds{ii}, 'OutputOnly');
          end
        end
        v = [obj.SignalGenerators.DefaultValue];
        obj.DaqSession.outputSingleScan(v(obj.AnalogueChannelsIdx));
        if any(~obj.AnalogueChannelsIdx)
          obj.DigitalDaqSession.outputSingleScan(v(~obj.AnalogueChannelsIdx));
        end
        obj.CurrValue = v;
      else
        obj.CurrValue = [];
      end
    end
    
    function command(obj, varargin)
      % Sends command signals to each channel
      %
      % command(channels, values)
      % sends command signals to each channel carrying each value.
      % 'channels' is a cell array of strings with each channel name, and
      % value is
      %
      % command(values)
      % sends command signals to all channels carrying each value
      %
      % [CHANNEL,INDEX] = addAnalogInputChannel(...)
      % addAnalogInputChannel optionally returns CHANNEL, which is an
      % object representing the channel that was added.  It also
      % returns INDEX, which is the index into the Channels array
      % where the channel was added.
      %
      % Example:
      %     s = daq.createSession('ni');
      %     s.addAnalogInputChannel('cDAQ1Mod1', 'ai0', 'Voltage');
      %     s.startForeground();
      %
      % See also addAnalogOutputChannel, removeChannel,
      % daq.getDevices
      values = varargin{1};
      if ischar(varargin{end})
        switch varargin{end}
          case {'fg' 'foreground'}
            foreground = true;
          case {'bg' 'background'}
            foreground = false;
          otherwise
            error('Unrecognised switch option "%s"', varargin{end});
        end
      else
        foreground = false;
      end
      n = size(values, 2);
      if n > 0
        gen = obj.SignalGenerators(1:n);
        rate = obj.DaqSession.Rate;
        waveforms = cell(1, n);
        for ii = 1:n
          if iscell(values)
            v = values{ii};
          else
            v = values(:,ii);
          end
          waveforms{ii} = gen(ii).waveform(rate, v);
        end
        if obj.DaqSession.IsRunning
          % if a daq operation is in progress, stop it, and set its output
          % to the default value
          reset(obj);
        end
        channelNames = obj.ChannelNames(1:n);
        analogueChannelsIdx = obj.AnalogueChannelsIdx(1:n);
        if any(analogueChannelsIdx)&&any(values(analogueChannelsIdx)~=0)
          queue(obj, channelNames(analogueChannelsIdx), waveforms(analogueChannelsIdx));
          if foreground
            startForeground(obj.DaqSession);
          else
            startBackground(obj.DaqSession);
          end
        elseif any(~analogueChannelsIdx)
            waveforms = waveforms(~analogueChannelsIdx);
            for n = 1:length(waveforms)
              digitalValues = waveforms{n};
              for m = 1:length(digitalValues)
                obj.DigitalDaqSession.outputSingleScan(digitalValues(m));
              end
            end
        end
      end
    end
    
    function v = get.NumChannels(obj)
      v = numel(obj.DaqChannelIds);
    end
    
    function v = get.AnalogueChannelsIdx(obj)
      v = cellfun(@(ch) any(lower(ch=='a')), obj.DaqChannelIds);
    end
    
    function v = get.Value(obj)
      v = obj.CurrValue;
    end
    
    function set.Value(obj, v)
      readyWait(obj);
      obj.DaqSession.outputSingleScan(v(obj.AnalogueChannelsIdx));
      if any(~obj.AnalogueChannelsIdx)
        obj.DigitalDaqSession.outputSingleScan(v(~obj.AnalogueChannelsIdx));
      end
      obj.CurrValue = v;
    end
    
    function reset(obj)
      stop(obj.DaqSession);
      if ~isempty(obj.DigitalDaqSession)
        stop(obj.DigitalDaqSession);
      end
      v = [obj.SignalGenerators.DefaultValue];
      outputSingleScan(obj.DaqSession, v(obj.AnalogueChannelsIdx));
      if any(~obj.AnalogueChannelsIdx)
        outputSingleScan(obj.DigitalDaqSession, v(~obj.AnalogueChannelsIdx));
      end
      obj.CurrValue = v;
    end
  end
  
  methods (Access = protected)
    function queue(obj, names, waveforms)
      names = ensureCell(names);
      waveforms = ensureCell(waveforms);
      assert(numel(names) == numel(waveforms),...
        'Number of channel names and waveforms not equal');
      len = cellfun(@numel, waveforms);
      defaultValues = [obj.SignalGenerators.DefaultValue];
      samples = repmat(defaultValues(obj.AnalogueChannelsIdx), max(len), 1);
      for ii = 1:numel(waveforms)
        cidx = strcmp(names{ii}, obj.ChannelNames);
        assert(sum(cidx) == 1, 'Channel name mismatch');
        samples(1:len(ii),cidx) = waveforms{ii};
      end
      readyWait(obj);
      %       plot(samples,'-x'), xlim([-1 300])
      obj.DaqSession.queueOutputData(samples);
      %       samplelen = size(samples,1)/1000
      %       dur = obj.DaqSession.DurationInSeconds
    end
    
    function readyWait(obj)
      if obj.DaqSession.IsRunning
        obj.DaqSession.wait();
      end
      if ~isempty(obj.DigitalDaqSession)&&obj.DigitalDaqSession.IsRunning
        obj.DigitalDaqSession.wait();
      end
    end
  end
  
end

