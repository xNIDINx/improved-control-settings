package nidin.control_settings.lobby
{
   import flash.display.MovieClip;
   import flash.display.DisplayObjectContainer;
   import net.wg.data.constants.generated.LAYER_NAMES;
   import net.wg.infrastructure.base.AbstractView;
   import net.wg.infrastructure.events.LoaderEvent;
   import net.wg.infrastructure.interfaces.IManagedContent;
   import net.wg.infrastructure.interfaces.ISimpleManagedContainer;
   import net.wg.infrastructure.interfaces.IView;
   import net.wg.infrastructure.managers.impl.ContainerManagerBase;
   import nidin.control_settings.settings.SettingsWrapper;

   public class LobbyHook extends AbstractView
   {
      public static const SETTINGS_WINDOW_LINKAGE:String = "settingsWindow";

      public var getProfiles:Function;

      public var saveProfiles:Function;

      public var onBridgeReady:Function;

      private var settingsWrapper:SettingsWrapper = null;
      private var wrappedWindow:IView = null;

      public function LobbyHook()
      {
         super();
      }

      public function as_setProfiles(param1:Object) : void
      {
         if(this.settingsWrapper != null)
         {
            this.settingsWrapper.setProfiles(param1);
         }
      }

      public function as_refreshSettings() : void
      {
         if(this.settingsWrapper != null)
         {
            // Python calls this after the complete native SettingsWindow._update,
            // including the final common provider assignment in as_setData.
            this.settingsWrapper.refreshSettings(true);
         }
      }

      public function getProfilesS() : Object
      {
         return this.getProfiles != null ? this.getProfiles() : {};
      }

      public function saveProfilesS(param1:Object) : Boolean
      {
         if(this.saveProfiles != null)
         {
            return Boolean(this.saveProfiles(param1));
         }
         return false;
      }

      private function _getContainer(param1:String) : ISimpleManagedContainer
      {
         return App.containerMgr.getContainer(LAYER_NAMES.LAYER_ORDER.indexOf(param1));
      }

      override protected function onPopulate() : void
      {
         super.onPopulate();
         var containerManager:ContainerManagerBase = App.containerMgr as ContainerManagerBase;
         containerManager.loader.addEventListener(LoaderEvent.VIEW_LOADED,this.onViewLoaded,false,0,true);
         // The hook can finish loading after a settings window has opened.
         // Windows are wrapped managed content, including in the battle app.
         for each(var layer:String in [LAYER_NAMES.VIEWS,LAYER_NAMES.WINDOWS,LAYER_NAMES.FULLSCREEN_WINDOWS])
         {
            var container:DisplayObjectContainer = this._getContainer(layer) as DisplayObjectContainer;
            if(container == null)
            {
               continue;
            }
            for(var index:int = 0; index < container.numChildren; index++)
            {
               var content:IManagedContent = container.getChildAt(index) as IManagedContent;
               if(content != null)
               {
                  this.processView(content.sourceView);
               }
            }
         }
      }

      override protected function onDispose() : void
      {
         var containerManager:ContainerManagerBase = App.containerMgr as ContainerManagerBase;
         containerManager.loader.removeEventListener(LoaderEvent.VIEW_LOADED,this.onViewLoaded);
         if(this.settingsWrapper != null)
         {
            this.settingsWrapper.dispose();
         }
         this.settingsWrapper = null;
         this.wrappedWindow = null;
         super.onDispose();
      }

      override protected function nextFrameAfterPopulateHandler() : void
      {
         super.nextFrameAfterPopulateHandler();
         if(parent != App.instance)
         {
            (App.instance as MovieClip).addChild(this);
         }
         // The bridge lives on App, but Wulf still owns an empty window in
         // OVERLAY. Hide that window through Python so it cannot take focus
         // ahead of the battle menu. Do this after native population/show.
         if(this.onBridgeReady != null)
         {
            this.onBridgeReady();
         }
      }

      private function onViewLoaded(param1:LoaderEvent) : void
      {
         this.processView(param1.view as IView);
      }

      private function processView(param1:IView) : void
      {
         if(param1 != null && param1 != this.wrappedWindow && param1.as_config.alias == SETTINGS_WINDOW_LINKAGE)
         {
            if(this.settingsWrapper != null)
            {
               this.settingsWrapper.dispose();
            }
            this.wrappedWindow = param1;
            this.settingsWrapper = new SettingsWrapper(param1,this);
         }
      }
   }
}
