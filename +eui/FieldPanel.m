classdef FieldPanel < handle
  %UNTITLED Summary of this class goes here
  %   Detailed explanation goes here
  
  properties
    MinCtrlWidth = 40
    MaxCtrlWidth = 140
    Margin = 4
    RowSpacing = 1
    ColSpacing = 3
    UIPanel
    ContextMenu
  end
  
  properties %(Access = protected)
    ParamEditor
    MinRowHeight
    Listener
    Labels
    Controls
    LabelWidths
  end
  
  events
    Changed
  end
  
  methods
    function obj = FieldPanel(f, ParamEditor, varargin)
      obj.ParamEditor = ParamEditor;
      p = uix.Panel('Parent', f);
      obj.UIPanel = uipanel('Parent', p, 'BorderType', 'none',...
          'BackgroundColor', 'white', 'Position', [0 0 0.5 1]);
      obj.Listener = event.listener(obj.UIPanel, 'SizeChanged', @obj.onResize);
    end

    function [label, ctrl] = addField(obj, name, ctrl)
      if isempty(obj.ContextMenu)
        obj.ContextMenu = uicontextmenu;
        uimenu(obj.ContextMenu, 'Label', 'Make Coditional', ...
          'MenuSelectedFcn', @(~,~)obj.makeConditional);
      end
      props.BackgroundColor = 'white';
      props.HorizontalAlignment = 'left';
      props.UIContextMenu = obj.ContextMenu;
      props.Parent = obj.UIPanel;
      label = uicontrol('Style', 'text', 'String', name, props);
      if nargin < 3
        ctrl = uicontrol('Style', 'edit', props);
      end
      callback = @(src,~)onEdit(obj, src, name);
      set(ctrl, 'Callback', callback);
      obj.Labels = [obj.Labels; label];
      obj.Controls = [obj.Controls; ctrl];
    end
    
    function onEdit(obj, src, id)
      disp(id);
      switch get(src, 'style')
        case 'checkbox'
          newValue = logical(get(src, 'value'));
          obj.ParamEditor.update(id, newValue);
        case 'edit'
          % if successful update the control with default formatting and
          % modified colour
          newValue = obj.ParamEditor.update(id, get(src, 'string'));
          set(src, 'String', obj.ParamEditor.paramValue2Control(newValue));
      end
      changed = strcmp(id,{obj.Labels.String});
      obj.Labels(changed).ForegroundColor = [1 0 0];
    end
    
    function clear(obj, idx) % FIXME Rename to clearFields
      if nargin == 1
        idx = true(size(obj.Labels));
      end
      delete(obj.Labels(idx))
      delete(obj.Controls(idx))
      obj.Labels(idx) = [];
      obj.LabelWidths(idx) = [];
      obj.Controls(idx) = [];
    end
    
    function makeConditional(obj, name)
      if nargin == 1
        selected = obj.UIPanel.Parent.CurrentObject; %FIXME Doesn't work is parent is not figure
        if isa(selected, 'matlab.ui.control.UIControl') && ...
            strcmp(selected.Style, 'text')
          name = selected.String;
        else % Assume control
          name = obj.Labels([obj.Controls]==selected).String;
        end
      end
      idx = strcmp(name,{obj.Labels.String});
      assert(~ismember(name, {'randomiseConditions'}), ...
        '%s can not be made a conditional parameter', name)
      
      obj.clear(idx);
      obj.ParamEditor.Parameters.makeTrialSpecific(name);
      obj.ParamEditor.fillConditionTable();
      obj.onResize;
    end
    
    function delete(obj)
      disp('delete called');
      delete(obj.UIPanel);
    end
       
    function onResize(obj, ~, ~)
      if isempty(obj.Controls)
        return
      end
      if isempty(obj.LabelWidths) || numel(obj.LabelWidths) ~= numel(obj.Labels)
        ext = reshape([obj.Labels.Extent], 4, [])';
        obj.LabelWidths = ext(:,3);
        l = uicontrol('Parent', obj.UIPanel, 'Style', 'edit', 'String', 'something');
        obj.MinRowHeight = l.Extent(4);
        delete(l);
      end
            
%       %%% resize condition table
%       w = numel(obj.ConditionTable.ColumnName);
% %       nCols = max(cols);
% %       globalWidth = (fullColWidth * nCols) + borderwidth;
%       if w > 5; w = 0.5; else; w = 0.1 * w; end
%       obj.UI(2).Position = [1-w 0 w 1];
%       obj.UI(1).Position = [0 0 1-w 1];
      
      %%% general coordinates
      pos = getpixelposition(obj.UIPanel);
      borderwidth = obj.Margin;
      bounds = [pos(3) pos(4)] - 2*borderwidth;
      n = numel(obj.Labels);
      vspace = obj.RowSpacing;
      hspace = obj.ColSpacing;
      rowHeight = obj.MinRowHeight + 2*vspace;
      rowsPerCol = floor(bounds(2)/rowHeight);
      cols = ceil((1:n)/rowsPerCol)';
      ncols = cols(end);
      rows = mod(0:n - 1, rowsPerCol)' + 1;
      labelColWidth = max(obj.LabelWidths) + 2*hspace;
      ctrlWidthAvail = bounds(1)/ncols - labelColWidth;
      ctrlColWidth = max(obj.MinCtrlWidth, min(ctrlWidthAvail, obj.MaxCtrlWidth));
      fullColWidth = labelColWidth + ctrlColWidth;
      
      %%% coordinates of labels
      by = bounds(2) - rows*rowHeight + vspace + 1 + borderwidth;
      labelPos = [vspace + (cols - 1)*fullColWidth + 1 + borderwidth...
        by...
        obj.LabelWidths...
        repmat(rowHeight - 2*vspace, n, 1)];
    
      %%% coordinates of edits
      editPos = [labelColWidth + hspace + (cols - 1)*fullColWidth + 1 + borderwidth ...
        by...
        repmat(ctrlColWidth - 2*hspace, n, 1)...
        repmat(rowHeight - 2*vspace, n, 1)];
      set(obj.Labels, {'Position'}, num2cell(labelPos, 2));
      set(obj.Controls, {'Position'}, num2cell(editPos, 2));
      
    end
  end
  
end

