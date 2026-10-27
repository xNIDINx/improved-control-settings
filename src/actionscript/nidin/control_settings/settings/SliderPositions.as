package nidin.control_settings.settings
{
   import net.wg.gui.components.controls.LabelControl;
   import net.wg.gui.components.controls.Slider;
   import net.wg.gui.lobby.settings.ControlsSettings;
   import scaleform.clik.events.SliderEvent;

   // Read-only labels; native sliders keep their ranges, spacing and behavior.
   public class SliderPositions
   {
      private static const NAMES:Array = ["mouseArcadeSensSlider","mouseSniperSensSlider","mouseStrategicSensSlider","mouseAssistAimSensSlider","mouseDeathFreecamSensSlider","mouseAssaultSensSlider"];
      private var controls:ControlsSettings;
      private var entries:Array = [];

      public function SliderPositions(owner:ControlsSettings)
      {
         controls = owner;
         for each(var name:String in NAMES)
         {
            if(!controls.hasOwnProperty(name))
            {
               continue;
            }
            var slider:Slider = controls[name] as Slider;
            if(slider == null)
            {
               continue;
            }
            var label:LabelControl = App.utils.classFactory.getComponent("LabelControl",LabelControl);
            label.name = "nidinMousePosition_" + name;
            label.width = 32;
            label.textAlign = "left";
            label.tabEnabled = false;
            label.validateNow();
            label.textField.selectable = false;
            controls.addChild(label);
            entries.push({"slider":slider,"label":label});
            slider.addEventListener(SliderEvent.FIRST_VALUE_CHANGE,this.onValueChanged,false,0,false);
            slider.addEventListener(SliderEvent.VALUE_CHANGE,this.onValueChanged,false,0,false);
         }
         this.syncLayout();
      }

      private function onValueChanged(event:SliderEvent) : void
      {
         this.syncLayout();
      }

      public function syncLayout() : void
      {
         if(controls == null)
         {
            return;
         }
         for each(var entry:Object in entries)
         {
            var slider:Slider = entry.slider;
            var label:LabelControl = entry.label;
            var range:Number = slider.maximum - slider.minimum;
            var ratio:Number = range > 0 ? (slider.value - slider.minimum) / range : 0;
            label.text = String(Math.round(Math.max(0,Math.min(1,ratio)) * 100));
            label.x = slider.x + slider.width + 4;
            label.y = slider.y + 2;
            label.visible = slider.visible && (controls.mouseFieldSet == null || controls.mouseFieldSet.visible);
            label.enabled = slider.enabled;
            label.mouseEnabled = false;
            label.mouseChildren = false;
         }
      }

      public function dispose() : void
      {
         for each(var entry:Object in entries)
         {
            var slider:Slider = entry.slider;
            var label:LabelControl = entry.label;
            slider.removeEventListener(SliderEvent.FIRST_VALUE_CHANGE,this.onValueChanged);
            slider.removeEventListener(SliderEvent.VALUE_CHANGE,this.onValueChanged);
            if(label.parent != null)
            {
               label.parent.removeChild(label);
            }
            label.dispose();
         }
         entries = [];
         controls = null;
      }
   }
}
