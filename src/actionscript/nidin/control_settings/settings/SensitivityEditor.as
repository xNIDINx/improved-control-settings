package nidin.control_settings.settings
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.FocusEvent;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.ui.Keyboard;
   import net.wg.gui.components.controls.LabelControl;
   import net.wg.gui.components.controls.Slider;
   import net.wg.gui.lobby.settings.ControlsSettings;
   import scaleform.clik.events.SliderEvent;

   public class SensitivityEditor
   {
      private static const ROW_SPACING:int = 8;
      private static const SLIDER_NAMES:Array = ["mouseArcadeSensSlider","mouseSniperSensSlider","mouseStrategicSensSlider","mouseAssistAimSensSlider","mouseDeathFreecamSensSlider","mouseAssaultSensSlider"];
      private static const SHIFTED_CONTROL_NAMES:Array = ["mouseHorzInvertCheckbox","mouseVertInvertCheckbox","backDraftInvertCheckbox"];

      private var controlsSettings:ControlsSettings = null;
      private var cleanupCallbacks:Array = [];
      private var layoutCallbacks:Array = [];
      private var layoutChanges:Array = [];
      private var disposed:Boolean = false;

      public function SensitivityEditor(controls:ControlsSettings)
      {
         super();
         controlsSettings = controls;
         this.installControls();
         this.syncLayout();
         App.utils.scheduler.scheduleOnNextFrame(this.syncLayout);
      }

      public function syncLayout() : void
      {
         if(disposed || controlsSettings == null)
         {
            return;
         }
         for each(var sync:Function in layoutCallbacks)
         {
            sync();
         }
      }

      public function dispose() : void
      {
         if(disposed)
         {
            return;
         }
         disposed = true;
         App.utils.scheduler.cancelTask(this.syncLayout);
         for each(var cleanup:Function in cleanupCallbacks)
         {
            cleanup();
         }
         cleanupCallbacks = [];
         layoutCallbacks = [];
         // Release the spacing owned by this editor without validating controls.
         for(var index:int = layoutChanges.length - 1; index >= 0; index--)
         {
            var change:Object = layoutChanges[index];
            change.target[change.property] -= change.amount;
         }
         layoutChanges = [];
         controlsSettings = null;
      }

      private function offsetControl(control:Object, property:String, amount:Number) : void
      {
         if(amount != 0)
         {
            control[property] += amount;
            layoutChanges.push({"target":control,"property":property,"amount":amount});
         }
      }

      private function installControls() : void
      {
         if(controlsSettings == null)
         {
            return;
         }
         var verticalOffset:int = 0;
         for each(var sliderName:String in SLIDER_NAMES)
         {
            if(this.addSliderValueText(controlsSettings,sliderName,verticalOffset))
            {
               verticalOffset += ROW_SPACING;
            }
         }
         var controlsOffset:int = Math.max(0,verticalOffset - ROW_SPACING);
         for each(var controlName:String in SHIFTED_CONTROL_NAMES)
         {
            if(controlsSettings.hasOwnProperty(controlName) && controlsSettings[controlName] != null)
            {
               this.offsetControl(controlsSettings[controlName],"y",controlsOffset);
            }
         }
         if(controlsSettings.mouseFieldSet != null && controlsSettings.mouseFieldSet.bg != null)
         {
            // FieldSet.draw() does not resize its frame from component height.
            // Stretch the actual frame, just as the native keyboard frame does.
            this.offsetControl(controlsSettings.mouseFieldSet.bg,"height",controlsOffset);
         }
      }

      private function addSliderValueText(param1:ControlsSettings, param2:String, param3:int) : Boolean
      {
         var slider:Slider = null;
         var lbl:LabelControl = null;
         var field:TextField = null;
         var frame:Sprite = null;
         var clickBlocker:Sprite = null;
         var frameColor:uint = 7828840;
         var originalFieldWidth:Number = Number(NaN);
         var originalFieldHeight:Number = Number(NaN);
         var stableFrameWidth:Number = Number(NaN);
         var stableFrameHeight:Number = Number(NaN);
         var drawnFrameWidth:Number = Number(NaN);
         var drawnFrameHeight:Number = Number(NaN);
         var drawnFrameColor:uint = 0;
         var drawnBlockerWidth:Number = Number(NaN);
         var drawnBlockerHeight:Number = Number(NaN);
         var updateCallback:Function = null;
         var commitCallback:Function = null;
         var liveChangeCallback:Function = null;
         var resizeFieldCallback:Function = null;
         var keyCallback:Function = null;
         var focusInCallback:Function = null;
         var blockClickCallback:Function = null;
         var layoutCallback:Function = null;
         var cleanupCallback:Function = null;
         var holder:ControlsSettings = param1;
         var sliderName:String = param2;
         var verticalOffset:int = param3;
         var labelName:String = sliderName.replace("Slider","Label");
         resizeFieldCallback = function():*
         {
            if(field != null && frame != null)
            {
               var frameWidth:Number = Math.ceil(field.textWidth) + 4;
               var frameHeight:Number = Math.ceil(field.textHeight) + 1;
               if(isNaN(stableFrameWidth))
               {
                  stableFrameWidth = frameWidth;
                  stableFrameHeight = frameHeight;
               }
               frameWidth = stableFrameWidth;
               frameHeight = stableFrameHeight;
               if(isNaN(drawnFrameWidth) || drawnFrameWidth != frameWidth || drawnFrameHeight != frameHeight)
               {
                  field.scrollRect = new Rectangle(0,0,frameWidth,frameHeight + 1);
               }
               if(isNaN(drawnFrameWidth) || drawnFrameWidth != frameWidth || drawnFrameHeight != frameHeight || drawnFrameColor != frameColor)
               {
                  frame.graphics.clear();
                  frame.graphics.lineStyle(1,frameColor,1);
                  frame.graphics.drawRect(0,0,frameWidth,frameHeight);
                  drawnFrameWidth = frameWidth;
                  drawnFrameHeight = frameHeight;
                  drawnFrameColor = frameColor;
               }
               frame.x = lbl.x + field.x;
               frame.y = lbl.y + field.y + 1;
               if(clickBlocker != null && !isNaN(originalFieldWidth))
               {
                  var blockerWidth:Number = Math.max(0,originalFieldWidth - frameWidth);
                  if(blockerWidth > 0)
                  {
                     if(isNaN(drawnBlockerWidth) || drawnBlockerWidth != blockerWidth || drawnBlockerHeight != originalFieldHeight)
                     {
                        clickBlocker.graphics.clear();
                        clickBlocker.graphics.beginFill(0,0.01);
                        clickBlocker.graphics.drawRect(0,0,blockerWidth,originalFieldHeight);
                        clickBlocker.graphics.endFill();
                        drawnBlockerWidth = blockerWidth;
                        drawnBlockerHeight = originalFieldHeight;
                     }
                     clickBlocker.x = frame.x + frameWidth;
                     clickBlocker.y = lbl.y + field.y;
                     clickBlocker.visible = lbl.visible;
                  }
                  else
                  {
                     clickBlocker.visible = false;
                  }
               }
            }
         };
         updateCallback = function():*
         {
            if(field == null || field.stage == null || field.stage.focus != field)
            {
               lbl.text = slider.value.toFixed(6);
               resizeFieldCallback();
            }
         };
         commitCallback = function(param1:FocusEvent = null):*
         {
            frameColor = 7828840;
            var text:String = field.text.replace(",",".");
            var parsed:Number = Number(text);
            if(text.length == 0 || isNaN(parsed))
            {
               lbl.text = slider.value.toFixed(6);
               resizeFieldCallback();
               return;
            }
            parsed = Math.max(slider.minimum,Math.min(slider.maximum,parsed));
            slider.value = parsed;
            lbl.text = slider.value.toFixed(6);
            resizeFieldCallback();
         };
         liveChangeCallback = function(param1:Event):*
         {
            var original:String = field.text;
            var sanitized:String = "";
            var separatorFound:Boolean = false;
            var decimalCount:int = 0;
            var i:int = 0;
            var character:String = null;
            while(i < original.length)
            {
               character = original.charAt(i);
               if(character >= "0" && character <= "9")
               {
                  if(!separatorFound || decimalCount < 6)
                  {
                     sanitized += character;
                     if(separatorFound)
                     {
                        decimalCount++;
                     }
                  }
               }
               else if((character == "." || character == ",") && !separatorFound)
               {
                  sanitized += character;
                  separatorFound = true;
               }
               i++;
            }
            if(sanitized != original)
            {
               field.text = sanitized;
               field.setSelection(sanitized.length,sanitized.length);
            }
            resizeFieldCallback();
            var normalized:String = sanitized.replace(",",".");
            if(normalized.length == 0 || normalized == ".")
            {
               return;
            }
            var parsed:Number = Number(normalized);
            if(isNaN(parsed))
            {
               return;
            }
            slider.value = Math.max(slider.minimum,Math.min(slider.maximum,parsed));
         };
         keyCallback = function(param1:KeyboardEvent):*
         {
            if(param1.keyCode == Keyboard.ENTER)
            {
               commitCallback();
               param1.stopImmediatePropagation();
               if(field.stage != null)
               {
                  field.stage.focus = null;
               }
            }
         };
         focusInCallback = function(param1:FocusEvent):*
         {
            frameColor = 12894640;
            resizeFieldCallback();
            field.setSelection(0,field.text.length);
         };
         blockClickCallback = function(param1:MouseEvent):*
         {
            param1.stopImmediatePropagation();
            if(field.stage != null && field.stage.focus == field)
            {
               field.stage.focus = null;
            }
         };
         if(!holder.hasOwnProperty(sliderName))
         {
            return false;
         }
         slider = holder[sliderName] as Slider;
         if(!slider)
         {
            return false;
         }
         this.offsetControl(slider,"y",verticalOffset);
         if(holder.hasOwnProperty(labelName) && holder[labelName] != null)
         {
            this.offsetControl(holder[labelName],"y",verticalOffset);
         }
         lbl = App.utils.classFactory.getComponent("LabelControl",LabelControl);
         lbl.name = "nidinMouseSensitivity_" + sliderName;
         lbl.y = slider.y + 20;
         slider.addEventListener(SliderEvent.FIRST_VALUE_CHANGE,updateCallback,false,0,false);
         slider.addEventListener(SliderEvent.VALUE_CHANGE,updateCallback,false,0,false);
         updateCallback();
         lbl.validateNow();
         lbl.x = slider.x + slider.width - lbl.width;
         lbl.hitArea = null;
         lbl.hitMc.mouseEnabled = false;
         lbl.mouseEnabled = false;
         lbl.mouseChildren = true;
         field = lbl.textField;
         originalFieldWidth = field.width;
         originalFieldHeight = field.height;
         field.border = false;
         field.mouseEnabled = true;
         field.selectable = true;
         field.type = TextFieldType.INPUT;
         field.restrict = "0-9.,";
         field.maxChars = 12;
         field.addEventListener(FocusEvent.FOCUS_IN,focusInCallback,false,0,false);
         field.addEventListener(FocusEvent.FOCUS_OUT,commitCallback,false,0,false);
         field.addEventListener(Event.CHANGE,liveChangeCallback,false,0,false);
         field.addEventListener(KeyboardEvent.KEY_DOWN,keyCallback,false,100,false);
         holder.addChild(lbl);
         frame = new Sprite();
         frame.name = lbl.name + "Frame";
         frame.mouseEnabled = false;
         frame.mouseChildren = false;
         holder.addChild(frame);
         clickBlocker = new Sprite();
         clickBlocker.name = lbl.name + "Blocker";
         clickBlocker.mouseEnabled = true;
         clickBlocker.mouseChildren = false;
         clickBlocker.addEventListener(MouseEvent.MOUSE_DOWN,blockClickCallback,false,100,false);
         holder.addChild(clickBlocker);
         resizeFieldCallback();
         layoutCallback = function():void
         {
            lbl.x = slider.x + slider.width - lbl.width;
            lbl.y = slider.y + 20;
            lbl.visible = slider.visible && (holder.mouseFieldSet == null || holder.mouseFieldSet.visible);
            frame.visible = lbl.visible;
            if(!lbl.visible && field.stage != null && field.stage.focus == field)
            {
               field.stage.focus = null;
            }
            resizeFieldCallback();
         };
         cleanupCallback = function():void
         {
            slider.removeEventListener(SliderEvent.FIRST_VALUE_CHANGE,updateCallback);
            slider.removeEventListener(SliderEvent.VALUE_CHANGE,updateCallback);
            field.removeEventListener(FocusEvent.FOCUS_IN,focusInCallback);
            field.removeEventListener(FocusEvent.FOCUS_OUT,commitCallback);
            field.removeEventListener(Event.CHANGE,liveChangeCallback);
            field.removeEventListener(KeyboardEvent.KEY_DOWN,keyCallback);
            clickBlocker.removeEventListener(MouseEvent.MOUSE_DOWN,blockClickCallback);
            // Removing a focused field during Cancel must not commit it again.
            if(field.stage != null && field.stage.focus == field)
            {
               field.stage.focus = null;
            }
            if(lbl.parent != null)
            {
               lbl.parent.removeChild(lbl);
            }
            lbl.dispose();
            if(frame.parent != null)
            {
               frame.parent.removeChild(frame);
            }
            frame.graphics.clear();
            if(clickBlocker.parent != null)
            {
               clickBlocker.parent.removeChild(clickBlocker);
            }
            clickBlocker.graphics.clear();
         };
         // Each strong listener is explicitly removed by its owned cleanup.
         layoutCallbacks.push(layoutCallback);
         cleanupCallbacks.push(cleanupCallback);
         return true;
      }
   }
}
