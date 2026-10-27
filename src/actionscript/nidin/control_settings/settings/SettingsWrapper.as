package nidin.control_settings.settings
{
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;
   import net.wg.gui.components.advanced.ButtonBarEx;
   import net.wg.gui.components.interfaces.INewCounter;
   import net.wg.gui.events.ListEventEx;
   import net.wg.gui.events.ViewStackEvent;
   import net.wg.gui.lobby.settings.ControlsSettings;
   import net.wg.gui.lobby.settings.SettingsWindow;
   import net.wg.gui.lobby.settings.config.SettingsConfigHelper;
   import net.wg.gui.lobby.settings.components.KeysItemRenderer;
   import net.wg.gui.lobby.settings.vo.SettingsViewData;
   import net.wg.infrastructure.events.LifeCycleEvent;
   import net.wg.infrastructure.interfaces.IView;
   import nidin.control_settings.lobby.LobbyHook;
   import scaleform.clik.data.DataProvider;
   import scaleform.clik.events.ButtonEvent;
   import scaleform.clik.events.IndexEvent;
   import scaleform.clik.interfaces.IDataProvider;

   public class SettingsWrapper
   {
      private static const CONTROLS_SETTINGS_LINKAGE:String = "ControlsSettings";
      private static const INSTALL_MARKER:String = "nidin_mode_control_profiles_controls";
      private static const MODE_COMMON:String = "common";
      private static const FALLBACK_TAB_HEIGHT:Number = 31;
      private static const PROFILE_INSTALL_DELAY:int = 100;
      private static const PROFILE_INSTALL_MAX_ATTEMPTS:int = 50;

      private static const MODES:Array = ["common","battleRoyale","comp7","frontline"];
      private static const TAB_DATA:Array = [
         {"label":"Общие настройки", "id":"common", "linkage":"common", "data":"common"},
         {"label":"Стальной охотник", "id":"battleRoyale", "linkage":"battleRoyale", "data":"battleRoyale"},
         {"label":"Натиск", "id":"comp7", "linkage":"comp7", "data":"comp7"},
         {"label":"Линия фронта", "id":"frontline", "linkage":"frontline", "data":"frontline"}
      ];

      // Native mouse controls are moved/hidden here; SensitivityEditor owns
      // their numeric fields and its additional row spacing.
      private static const MOUSE_SLIDER_NAMES:Array = [
         "mouseArcadeSensSlider","mouseSniperSensSlider","mouseStrategicSensSlider",
         "mouseAssistAimSensSlider","mouseDeathFreecamSensSlider","mouseAssaultSensSlider"
      ];
      private static const MOUSE_CHECKBOX_NAMES:Array = [
         "mouseHorzInvertCheckbox","mouseVertInvertCheckbox","backDraftInvertCheckbox"
      ];

      private var settingsWindow:SettingsWindow = null;
      private var controlsSettings:ControlsSettings = null;
      private var hook:LobbyHook = null;
      private var profileTabs:ButtonBarEx = null;
      private var profileTabsDonor:MovieClip = null;
      private var controlsBackground:DisplayObject = null;
      private var controlsBackgroundMask:Sprite = null;
      private var commonKeysProvider:IDataProvider = null;
      private var modeKeysProviders:Object = null;
      private var profileKeys:Object = null;
      private var profileChanges:Object = {};
      private var profilesDirty:Boolean = false;
      private var changingProvider:Boolean = false;
      private var currentMode:String = MODE_COMMON;
      private var profileInstallAttempts:int = 0;
      private var profileTabsHeight:Number = FALLBACK_TAB_HEIGHT;
      private var profileTabsVisualHeight:Number = FALLBACK_TAB_HEIGHT;
      private var controlsLayoutSnapshot:Object = null;
      private var controlsLayoutReady:Boolean = false;
      private var sensitivityEditor:SensitivityEditor = null;
      private var digitalSensitivityEnabled:Boolean = true;
      private var sliderPositions:SliderPositions = null;
      private var sliderPositionsEnabled:Boolean = false;
      private var hiddenNativeCounters:Dictionary = new Dictionary(true);
      private var disposed:Boolean = false;

      public function SettingsWrapper(param1:IView, param2:LobbyHook)
      {
         super();
         settingsWindow = param1 as SettingsWindow;
         hook = param2;
         if(settingsWindow == null || hook == null)
         {
            return;
         }
         digitalSensitivityEnabled = hook.isDigitalSensitivityEnabledS();
         sliderPositionsEnabled = !digitalSensitivityEnabled && hook.isSliderPositionsEnabledS();
         settingsWindow.view.addEventListener(ViewStackEvent.VIEW_CHANGED,this.onViewStackEventHandler);
         settingsWindow.view.addEventListener(ViewStackEvent.NEED_UPDATE,this.onViewStackEventHandler);
         settingsWindow.addEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE,this.handleSettingsWindowBeforeDispose);
         settingsWindow.applyBtn.addEventListener(ButtonEvent.CLICK,this.onCommitClick,false,1000,true);
         settingsWindow.submitBtn.addEventListener(ButtonEvent.CLICK,this.onCommitClick,false,1000,true);
         settingsWindow.applyBtn.addEventListener(ButtonEvent.CLICK,this.onCommitFinished,false,-1000,true);
         settingsWindow.submitBtn.addEventListener(ButtonEvent.CLICK,this.onCommitFinished,false,-1000,true);
         App.utils.scheduler.scheduleOnNextFrame(this.onSettingsWindowOpened);
      }

      public function setProfiles(param1:Object) : void
      {
         if(disposed)
         {
            return;
         }
         profileKeys = param1 != null ? param1 : {};
         modeKeysProviders = {};
      }

      public function refreshSettings(immediate:Boolean = false) : void
      {
         if(disposed)
         {
            return;
         }
         App.utils.scheduler.cancelTask(this.refreshNativeProvider);
         if(immediate)
         {
            this.refreshNativeProvider();
         }
         // ViewStack events can precede the final native setData. Keep the
         // deferred reconciliation, but never rely on it to finish Apply.
         App.utils.scheduler.scheduleOnNextFrame(this.refreshNativeProvider);
      }

      private function refreshNativeProvider() : void
      {
         if(disposed || controlsSettings == null || profileTabs == null || !controlsLayoutReady)
         {
            return;
         }
         var provider:IDataProvider = controlsSettings.keys.dataProvider;
         // Native as_setData recreates the keyboard provider after Apply.
         // Adopt the new common list before restoring the selected mode.
         if(provider != commonKeysProvider && provider != modeKeysProviders[currentMode])
         {
            commonKeysProvider = provider;
         }
         this.showMode(currentMode);
         if(profilesDirty)
         {
            settingsWindow.applyBtn.enabled = true;
         }
      }

      private function onSettingsWindowOpened() : void
      {
         if(disposed || settingsWindow == null || settingsWindow.view == null || settingsWindow.view.currentViewId != CONTROLS_SETTINGS_LINKAGE)
         {
            return;
         }
         controlsSettings = settingsWindow.view.currentView as ControlsSettings;
         this.hookControlsSettings();
      }

      private function onViewStackEventHandler(param1:ViewStackEvent) : void
      {
         if(disposed)
         {
            return;
         }
         if(param1.viewId == CONTROLS_SETTINGS_LINKAGE)
         {
            controlsSettings = param1.view as ControlsSettings;
            this.hookControlsSettings();
            this.refreshSettings();
         }
         this.syncProfileTabsVisibility();
      }

      private function isControlsCurrent() : Boolean
      {
         return !disposed && settingsWindow != null && settingsWindow.view != null &&
            controlsSettings != null && settingsWindow.view.currentView === controlsSettings &&
            settingsWindow.view.currentViewId == CONTROLS_SETTINGS_LINKAGE;
      }

      private function syncProfileTabsVisibility() : void
      {
         if(profileTabsDonor != null)
         {
            // NEED_UPDATE can describe a page before ViewStack selects it.
            profileTabsDonor.visible = controlsLayoutReady && this.isControlsCurrent();
         }
      }

      private function hookControlsSettings() : void
      {
         if(disposed || controlsSettings == null)
         {
            return;
         }
         // Native unread markers may be added after the form or after Apply.
         controlsSettings.addEventListener(Event.ADDED,this.onNativeCounterAdded);
         if(!controlsSettings.hasOwnProperty(INSTALL_MARKER))
         {
            controlsSettings[INSTALL_MARKER] = true;
         }
         if(profileTabs == null)
         {
            App.utils.scheduler.cancelTask(this.retryInstallProfileTabs);
            profileInstallAttempts = 0;
            this.retryInstallProfileTabs();
         }
      }

      private function retryInstallProfileTabs() : void
      {
         if(disposed || controlsSettings == null || profileTabs != null || profileTabsDonor != null)
         {
            return;
         }
         if(this.installProfileTabs())
         {
            return;
         }
         profileInstallAttempts++;
         if(profileInstallAttempts < PROFILE_INSTALL_MAX_ATTEMPTS)
         {
            App.utils.scheduler.scheduleTask(this.retryInstallProfileTabs,PROFILE_INSTALL_DELAY);
         }
      }

      private function installProfileTabs() : Boolean
      {
         if(controlsSettings.keys == null || controlsSettings.keys.dataProvider == null || controlsSettings.keys.dataProvider.length == 0)
         {
            return false;
         }
         profileTabsDonor = App.utils.classFactory.getComponent("AimSettings",MovieClip) as MovieClip;
         if(profileTabsDonor == null)
         {
            return false;
         }
         profileTabsDonor.visible = false;
         profileTabsDonor.name = "nidinModeControlProfileTabsDonor";
         controlsSettings.addChild(profileTabsDonor);
         App.utils.scheduler.scheduleOnNextFrame(this.finishProfileTabsInstall);
         return true;
      }

      private function finishProfileTabsInstall() : void
      {
         if(disposed || controlsSettings == null || profileTabsDonor == null || profileTabsDonor.tabs == null)
         {
            return;
         }
         profileTabsHeight = profileTabsDonor.arcadeForm != null && profileTabsDonor.arcadeForm.y > 0 ? profileTabsDonor.arcadeForm.y : FALLBACK_TAB_HEIGHT;
         profileTabsVisualHeight = profileTabsDonor.bg != null && profileTabsDonor.bg.y > 0 ? profileTabsDonor.bg.y : profileTabsHeight;
         profileTabsDonor.scrollRect = new Rectangle(0,0,controlsSettings.width,profileTabsVisualHeight);
         if(profileTabsDonor.parent != null)
         {
            profileTabsDonor.parent.removeChild(profileTabsDonor);
         }
         profileTabsDonor.x = settingsWindow.view.x;
         profileTabsDonor.y = settingsWindow.view.y;
         settingsWindow.addChild(profileTabsDonor);
         this.clipControlsBackgroundBelowTabs();
         profileTabs = profileTabsDonor.tabs;
         profileTabs.dataProvider = new DataProvider(TAB_DATA);
         profileTabs.addEventListener(IndexEvent.INDEX_CHANGE,this.onProfileTabChanged,false,0,true);
         commonKeysProvider = controlsSettings.keys.dataProvider;
         profileKeys = hook.getProfilesS();
         if(profileKeys == null)
         {
            profileKeys = {};
         }
         modeKeysProviders = {};
         controlsSettings.keys.addEventListener(ListEventEx.ITEM_TEXT_CHANGE,this.onKeysItemTextChangeHandler,false,1000,true);
         controlsSettings.visible = false;
         profileTabsDonor.visible = false;
         App.utils.scheduler.scheduleOnNextFrame(this.finishControlsLayoutAfterNativeValidation);
      }

      private function finishControlsLayoutAfterNativeValidation() : void
      {
         if(disposed || controlsSettings == null || profileTabsDonor == null || profileTabs == null)
         {
            return;
         }
         controlsSettings.validateNow();
         controlsSettings.keyboardFieldSet.validateNow();
         controlsSettings.keys.validateNow();
         // Both features are installed by this one window owner after native
         // validation. The editor contributes spacing before the tabs move it.
         if(digitalSensitivityEnabled && sensitivityEditor == null)
         {
            sensitivityEditor = new SensitivityEditor(controlsSettings);
         }
         else if(sliderPositionsEnabled && sliderPositions == null)
         {
            sliderPositions = new SliderPositions(controlsSettings);
         }
         this.makeRoomForProfileTabs();
         controlsLayoutReady = true;
         profileTabs.selectedIndex = 0;
         profileTabs.validateNow();
         this.showMode(MODE_COMMON);
         // Restore only the page hidden during this initial layout pass.
         // The user may have selected another page while callbacks waited.
         if(this.isControlsCurrent())
         {
            controlsSettings.visible = true;
         }
         this.syncProfileTabsVisibility();
      }

      private function makeRoomForProfileTabs() : void
      {
         var slider:Object = null;
         var label:Object = null;
         var checkbox:Object = null;
         this.captureControlsLayout();
         var contentShift:Number = profileTabsVisualHeight;
         controlsSettings.keyboardFieldSet.y = controlsLayoutSnapshot.keyboardFieldSetY + contentShift;
         controlsSettings.keyboardFieldSet.bg.height = Math.max(40,controlsLayoutSnapshot.keyboardFrameHeight - contentShift);
         controlsSettings.keys.y = controlsLayoutSnapshot.keysY + contentShift;
         if(controlsSettings.keys.maskObject != null)
         {
            controlsSettings.keys.maskObject.graphics.clear();
         }
         controlsSettings.keys.setSize(controlsLayoutSnapshot.keysWidth,Math.max(40,controlsLayoutSnapshot.keysHeight - contentShift));
         controlsSettings.scrollBar.y = controlsLayoutSnapshot.scrollBarY + contentShift;
         controlsSettings.scrollBar.setSize(controlsLayoutSnapshot.scrollBarWidth,Math.max(40,controlsLayoutSnapshot.scrollBarHeight - contentShift));
         controlsSettings.mouseFieldSet.y = controlsLayoutSnapshot.mouseFieldSetY + contentShift;
         if(controlsSettings.mouseSensitivityLabel != null)
         {
            controlsSettings.mouseSensitivityLabel.y = controlsLayoutSnapshot.mouseSensitivityLabelY + contentShift;
         }
         for each(var sliderName:String in MOUSE_SLIDER_NAMES)
         {
            if(controlsSettings.hasOwnProperty(sliderName) && controlsSettings[sliderName] != null)
            {
               slider = controlsSettings[sliderName];
               slider.y = controlsLayoutSnapshot.componentY[sliderName] + contentShift;
            }
            var labelName:String = sliderName.replace("Slider","Label");
            if(controlsSettings.hasOwnProperty(labelName) && controlsSettings[labelName] != null)
            {
               label = controlsSettings[labelName];
               label.y = controlsLayoutSnapshot.componentY[labelName] + contentShift;
            }
         }
         for each(var checkboxName:String in MOUSE_CHECKBOX_NAMES)
         {
            if(controlsSettings.hasOwnProperty(checkboxName) && controlsSettings[checkboxName] != null)
            {
               checkbox = controlsSettings[checkboxName];
               checkbox.y = controlsLayoutSnapshot.componentY[checkboxName] + contentShift;
            }
         }
         this.syncSensitivityLayout();
      }

      private function clipControlsBackgroundBelowTabs() : void
      {
         if(controlsBackgroundMask != null || controlsSettings.numChildren == 0)
         {
            return;
         }
         var background:DisplayObject = controlsSettings.getChildAt(0);
         if(getQualifiedClassName(background).split("::").pop() != "Window_BGForm" || background.mask != null)
         {
            return;
         }
         // Unselected native tabs are translucent. Keep the same background
         // beneath them as 0.7.6, without masking the interactive controls.
         var bounds:Rectangle = background.getBounds(controlsSettings);
         var top:Number = Math.max(bounds.y,profileTabsVisualHeight);
         controlsBackgroundMask = new Sprite();
         controlsBackgroundMask.mouseEnabled = false;
         controlsBackgroundMask.mouseChildren = false;
         controlsBackgroundMask.graphics.beginFill(0xFFFFFF,1);
         controlsBackgroundMask.graphics.drawRect(bounds.x,top,bounds.width,Math.max(1,bounds.bottom - top));
         controlsBackgroundMask.graphics.endFill();
         controlsSettings.addChild(controlsBackgroundMask);
         controlsBackground = background;
         controlsBackground.mask = controlsBackgroundMask;
      }

      private function restoreControlsBackground() : void
      {
         if(controlsBackground != null && controlsBackground.mask == controlsBackgroundMask)
         {
            controlsBackground.mask = null;
         }
         if(controlsBackgroundMask != null)
         {
            if(controlsBackgroundMask.parent != null)
            {
               controlsBackgroundMask.parent.removeChild(controlsBackgroundMask);
            }
            controlsBackgroundMask.graphics.clear();
         }
         controlsBackground = null;
         controlsBackgroundMask = null;
      }

      private function captureControlsLayout() : void
      {
         if(controlsLayoutSnapshot != null)
         {
            return;
         }
         var componentY:Object = {};
         for each(var sliderName:String in MOUSE_SLIDER_NAMES)
         {
            if(controlsSettings.hasOwnProperty(sliderName) && controlsSettings[sliderName] != null)
            {
               componentY[sliderName] = controlsSettings[sliderName].y;
            }
            var labelName:String = sliderName.replace("Slider","Label");
            if(controlsSettings.hasOwnProperty(labelName) && controlsSettings[labelName] != null)
            {
               componentY[labelName] = controlsSettings[labelName].y;
            }
         }
         for each(var checkboxName:String in MOUSE_CHECKBOX_NAMES)
         {
            if(controlsSettings.hasOwnProperty(checkboxName) && controlsSettings[checkboxName] != null)
            {
               componentY[checkboxName] = controlsSettings[checkboxName].y;
            }
         }
         controlsLayoutSnapshot = {
            "keyboardFieldSetY":controlsSettings.keyboardFieldSet.y,
            "keyboardFrameHeight":controlsSettings.keyboardFieldSet.bg.height,
            "keysY":controlsSettings.keys.y,
            "keysWidth":controlsSettings.keys.width,
            "keysHeight":controlsSettings.keys.height,
            "scrollBarY":controlsSettings.scrollBar.y,
            "scrollBarWidth":controlsSettings.scrollBar.width,
            "scrollBarHeight":controlsSettings.scrollBar.height,
            "mouseFieldSetY":controlsSettings.mouseFieldSet.y,
            "mouseSensitivityLabelY":controlsSettings.mouseSensitivityLabel != null ? controlsSettings.mouseSensitivityLabel.y : 0,
            "componentY":componentY
         };
      }

      private function onProfileTabChanged(param1:IndexEvent) : void
      {
         if(disposed || !controlsLayoutReady)
         {
            return;
         }
         if(param1.index >= 0 && param1.index < MODES.length)
         {
            this.showMode(String(MODES[param1.index]));
         }
      }

      private function showMode(param1:String) : void
      {
         currentMode = param1;
         if(param1 == MODE_COMMON)
         {
            this.setKeysProvider(commonKeysProvider);
            controlsSettings.keys.visible = true;
            controlsSettings.scrollBar.visible = true;
            this.setCommonControlsVisible(true);
            controlsSettings.keys.scrollPosition = 0;
            controlsSettings.keys.validateNow();
         }
         else
         {
            this.setKeysProvider(this.getModeKeysProvider(param1));
            controlsSettings.keys.visible = true;
            controlsSettings.scrollBar.visible = controlsSettings.keys.maxScroll > 0;
            this.setCommonControlsVisible(false);
         }
      }

      private function getModeKeysProvider(param1:String) : IDataProvider
      {
         // Each mode has a persisted snapshot, independent of common edits.
         if(modeKeysProviders[param1] == null)
         {
            modeKeysProviders[param1] = new DataProvider(this.createEquipmentItems(param1));
         }
         return modeKeysProviders[param1] as IDataProvider;
      }

      private function createEquipmentItems(param1:String) : Array
      {
         var result:Array = [];
         var item:Object = null;
         var clonedItem:Object = null;
         var inEquipment:Boolean = false;
         var firstSectionYOffset:Number = 0;
         var equipmentLabel:String = App.utils.locale.makeString(SETTINGS.KEYBOARD_KEYSBLOCKS_GROUP_EQUIPMENT);
         if(commonKeysProvider == null)
         {
            return result;
         }
         var firstItem:Object = commonKeysProvider.requestItemAt(0);
         if(firstItem != null && firstItem.hasOwnProperty("rendererYOffset"))
         {
            firstSectionYOffset = Number(firstItem.rendererYOffset);
         }
         var index:int = 0;
         while(index < commonKeysProvider.length)
         {
            item = commonKeysProvider.requestItemAt(index);
            if(item != null && item.header)
            {
               if(inEquipment)
               {
                  break;
               }
               inEquipment = item.label == equipmentLabel;
            }
            if(inEquipment && item != null)
            {
               clonedItem = this.cloneKeyItem(item);
               if(!clonedItem.header && profileKeys != null && profileKeys[param1] != null && profileKeys[param1].hasOwnProperty(clonedItem.command))
               {
                  clonedItem.key = Number(profileKeys[param1][clonedItem.command]);
               }
               if(result.length == 0)
               {
                  clonedItem.rendererYOffset = firstSectionYOffset;
               }
               result.push(clonedItem);
            }
            index++;
         }
         return result;
      }

      private function cloneKeyItem(param1:Object) : Object
      {
         var result:Object = {};
         for(var field:String in param1)
         {
            result[field] = param1[field] is Array ? param1[field].concat() : param1[field];
         }
         return result;
      }

      private function setKeysProvider(param1:IDataProvider) : void
      {
         if(disposed || param1 == null || controlsSettings == null || controlsSettings.keys == null)
         {
            return;
         }
         changingProvider = true;
         try
         {
            this.replaceKeysProvider(param1);
            this.validateKeyRenderers();
         }
         finally
         {
            changingProvider = false;
         }
      }

      private function replaceKeysProvider(param1:IDataProvider) : void
      {
         if(controlsSettings.keys.dataProvider == param1)
         {
            controlsSettings.keys.scrollPosition = 0;
            controlsSettings.keys.validateNow();
            App.utils.scheduler.scheduleOnNextFrame(this.refreshScrollBarAfterProviderChange);
            return;
         }
         // Native KeysScrollingList can rebind existing rows, but cannot
         // resize/reflow them. Reuse the identical equipment layout across
         // modes; rebuild only when switching to a different list structure.
         if(!this.canReuseKeyRenderers(param1))
         {
            controlsSettings.keys.disposeRenderers();
            controlsSettings.keys.itemRendererList = null;
            controlsSettings.keys.container = new Sprite();
            controlsSettings.keys.container.name = "container";
            controlsSettings.keys.addChildAt(controlsSettings.keys.container,0);
         }
         controlsSettings.keys.dataProvider = param1;
         controlsSettings.keys.scrollPosition = 0;
         controlsSettings.keys.invalidateRenderers();
         controlsSettings.keys.validateNow();
         App.utils.scheduler.scheduleOnNextFrame(this.refreshScrollBarAfterProviderChange);
      }

      private function canReuseKeyRenderers(provider:IDataProvider) : Boolean
      {
         var previous:IDataProvider = controlsSettings.keys.dataProvider;
         if(previous == null || previous.length != provider.length || controlsSettings.keys.getRendererAt(provider.length) != null)
         {
            return false;
         }
         for(var index:int = 0; index < provider.length; index++)
         {
            var before:Object = previous.requestItemAt(index);
            var after:Object = provider.requestItemAt(index);
            if(controlsSettings.keys.getRendererAt(index) == null || before == null || after == null || before.id != after.id || before.header != after.header || before.label != after.label || before.rendererYOffset != after.rendererYOffset || before.additionalDiscr != after.additionalDiscr || before.tooltipID != after.tooltipID || before.showUnderline != after.showUnderline)
            {
               return false;
            }
         }
         return true;
      }

      private function validateKeyRenderers() : void
      {
         var provider:IDataProvider = controlsSettings.keys.dataProvider;
         for(var index:int = 0; index < provider.length; index++)
         {
            var renderer:KeysItemRenderer = controlsSettings.keys.getRendererAt(index) as KeysItemRenderer;
            if(renderer == null)
            {
               continue;
            }
            // Flush both levels before releasing changingProvider. Deferred
            // KEY_NONE setup emits CHANGE, and key captions otherwise lag a
            // frame behind the list. A key capture must not follow a new tab.
            if(renderer.keyInput != null)
            {
               renderer.keyInput.selected = false;
            }
            renderer.validateNow();
            if(renderer.keyInput != null)
            {
               renderer.keyInput.validateNow();
            }
         }
      }

      private function refreshScrollBarAfterProviderChange() : void
      {
         if(disposed || controlsSettings == null || controlsSettings.keys == null || controlsSettings.scrollBar == null)
         {
            return;
         }
         controlsSettings.keys.validateNow();
         var maximum:Number = Math.max(0,controlsSettings.keys.maxScroll);
         var pageSize:Number = controlsSettings.keys.scrollPageSize;
         controlsSettings.scrollBar.setScrollProperties(pageSize,0,maximum);
         controlsSettings.scrollBar.trackScrollPageSize = pageSize;
         controlsSettings.scrollBar.position = controlsSettings.keys.scrollPosition;
         controlsSettings.scrollBar.validateNow();
         controlsSettings.scrollBar.visible = currentMode == MODE_COMMON || maximum > 0;
      }

      private function onKeysItemTextChangeHandler(param1:ListEventEx) : void
      {
         if(disposed)
         {
            return;
         }
         if(changingProvider)
         {
            // KeyInput.setupKey emits CHANGE for KEY_NONE while initializing
            // renderers. These are not edits and must not dirty either profile.
            param1.stopImmediatePropagation();
            return;
         }
         if(currentMode != MODE_COMMON && controlsSettings.keys.dataProvider == modeKeysProviders[currentMode])
         {
            // The renderer has already updated the private provider (including
            // clearing a duplicate equipment key). Snapshot all ten bindings,
            // then prevent ControlsSettings from writing them globally.
            profileKeys[currentMode] = this.snapshotProvider(controlsSettings.keys.dataProvider);
            profileChanges[currentMode] = profileKeys[currentMode];
            profilesDirty = true;
            settingsWindow.applyBtn.enabled = true;
            settingsWindow.submitBtn.enabled = true;
            param1.stopImmediatePropagation();
            // The native handler is suppressed, so refresh cleared duplicates.
            controlsSettings.keys.updateDataProvider();
         }
      }

      private function snapshotProvider(param1:IDataProvider) : Object
      {
         var result:Object = {};
         var item:Object = null;
         var index:int = 0;
         if(param1 == null)
         {
            return result;
         }
         while(index < param1.length)
         {
            item = param1.requestItemAt(index);
            if(item != null && !item.header && item.command != null)
            {
               result[String(item.command)] = Number(item.key);
            }
            index++;
         }
         return result;
      }

      private function onCommitClick(param1:ButtonEvent) : void
      {
         if(disposed)
         {
            return;
         }
         if(profilesDirty && hook != null)
         {
            if(!hook.saveProfilesS(profileChanges))
            {
               param1.stopImmediatePropagation();
               return;
            }
            profileChanges = {};
            profilesDirty = false;
         }
         // Native validation reads important bindings from the common list.
         // The lower-priority listener restores the mode before another frame.
         if(commonKeysProvider != null)
         {
            this.setKeysProvider(commonKeysProvider);
            this.refreshSettings();
         }
      }

      private function onCommitFinished(param1:ButtonEvent) : void
      {
         // Native Apply/OK runs at priority 0. It may also close this window;
         // refreshSettings checks disposed before touching any native controls.
         this.refreshSettings(true);
      }

      private function setCommonControlsVisible(param1:Boolean) : void
      {
         if(controlsSettings.mouseFieldSet != null)
         {
            controlsSettings.mouseFieldSet.visible = param1;
         }
         if(controlsSettings.mouseSensitivityLabel != null)
         {
            controlsSettings.mouseSensitivityLabel.visible = param1;
         }
         if(controlsSettings.defaultBtn != null)
         {
            controlsSettings.defaultBtn.visible = param1;
         }
         for each(var sliderName:String in MOUSE_SLIDER_NAMES)
         {
            if(controlsSettings.hasOwnProperty(sliderName) && controlsSettings[sliderName] != null)
            {
               controlsSettings[sliderName].visible = param1;
            }
            var labelName:String = sliderName.replace("Slider","Label");
            if(controlsSettings.hasOwnProperty(labelName) && controlsSettings[labelName] != null)
            {
               controlsSettings[labelName].visible = param1;
            }
         }
         for each(var checkboxName:String in MOUSE_CHECKBOX_NAMES)
         {
            if(controlsSettings.hasOwnProperty(checkboxName) && controlsSettings[checkboxName] != null)
            {
               controlsSettings[checkboxName].visible = param1;
            }
         }
         this.syncSensitivityLayout();
      }

      private function syncSensitivityLayout() : void
      {
         if(sliderPositions != null)
         {
            sliderPositions.syncLayout();
         }
         if(sensitivityEditor != null)
         {
            sensitivityEditor.syncLayout();
         }
         if(disposed || controlsSettings == null)
         {
            return;
         }
         // CounterBase listens to its parent's RESIZE and uses its own target
         // and offsets. Move existing markers after both of our layout shifts.
         controlsSettings.dispatchEvent(new Event(Event.RESIZE));
         for(var index:int = 0; index < controlsSettings.numChildren; index++)
         {
            this.syncNativeCounterVisibility(controlsSettings.getChildAt(index));
         }
      }

      private function onNativeCounterAdded(event:Event) : void
      {
         if(!disposed)
         {
            this.syncNativeCounterVisibility(event.target as DisplayObject);
         }
      }

      private function syncNativeCounterVisibility(counter:DisplayObject) : void
      {
         // Mouse controls and Reset are direct children of this form. Keyboard
         // row markers and counters on the window tabs belong to other parents.
         if(counter == null || !(counter is INewCounter) || counter.parent != controlsSettings)
         {
            return;
         }
         if(currentMode != MODE_COMMON)
         {
            if(!(counter in hiddenNativeCounters))
            {
               hiddenNativeCounters[counter] = counter.alpha;
            }
            // Native deferred validation sets visible=true. Alpha hides the
            // marker through that validation without changing its unread state.
            counter.alpha = 0;
         }
         else if(counter in hiddenNativeCounters)
         {
            counter.alpha = Number(hiddenNativeCounters[counter]);
            delete hiddenNativeCounters[counter];
         }
      }

      private function restoreNativeCounters() : void
      {
         for(var counter:Object in hiddenNativeCounters)
         {
            DisplayObject(counter).alpha = Number(hiddenNativeCounters[counter]);
         }
         hiddenNativeCounters = new Dictionary(true);
      }

      private function handleSettingsWindowBeforeDispose(param1:LifeCycleEvent) : void
      {
         if(param1.target !== settingsWindow)
         {
            return;
         }
         this.dispose();
      }

      // A live opt-out differs from window destruction: restore the native
      // provider and geometry while controls still exist, then detach our UI.
      public function deactivate() : void
      {
         if(disposed)
         {
            return;
         }
         var controls:ControlsSettings = controlsSettings;
         var wasCurrent:Boolean = this.isControlsCurrent();
         try
         {
            this.cancelPendingTasks();
            if(controls != null)
            {
               currentMode = MODE_COMMON;
               if(commonKeysProvider != null)
               {
                  this.setKeysProvider(commonKeysProvider);
               }
               this.setCommonControlsVisible(true);
               this.restoreControlsLayout();
               controls.keys.visible = true;
               this.refreshScrollBarAfterProviderChange();
            }
         }
         finally
         {
            // The snapshot includes the editor's spacing. Undo the profile
            // shift first; editor disposal then removes only its own offsets.
            this.dispose();
            if(controls != null)
            {
               if(wasCurrent)
               {
                  controls.visible = true;
               }
               controls.dispatchEvent(new Event(Event.RESIZE));
            }
         }
      }

      private function restoreControlsLayout() : void
      {
         if(controlsSettings == null || controlsLayoutSnapshot == null)
         {
            return;
         }
         var snapshot:Object = controlsLayoutSnapshot;
         controlsSettings.keyboardFieldSet.y = snapshot.keyboardFieldSetY;
         controlsSettings.keyboardFieldSet.bg.height = snapshot.keyboardFrameHeight;
         controlsSettings.keys.y = snapshot.keysY;
         if(controlsSettings.keys.maskObject != null)
         {
            controlsSettings.keys.maskObject.graphics.clear();
         }
         controlsSettings.keys.setSize(snapshot.keysWidth,snapshot.keysHeight);
         controlsSettings.scrollBar.y = snapshot.scrollBarY;
         controlsSettings.scrollBar.setSize(snapshot.scrollBarWidth,snapshot.scrollBarHeight);
         controlsSettings.mouseFieldSet.y = snapshot.mouseFieldSetY;
         if(controlsSettings.mouseSensitivityLabel != null)
         {
            controlsSettings.mouseSensitivityLabel.y = snapshot.mouseSensitivityLabelY;
         }
         for(var name:String in snapshot.componentY)
         {
            if(controlsSettings.hasOwnProperty(name) && controlsSettings[name] != null)
            {
               controlsSettings[name].y = snapshot.componentY[name];
            }
         }
      }

      public function dispose() : void
      {
         if(disposed)
         {
            return;
         }
         // Native as_dispose and UIComponent.doDispose can both send this
         // event. Disable callbacks before touching children or releasing focus.
         disposed = true;
         controlsLayoutReady = false;
         for each(var cleanup:Function in [this.cancelPendingTasks,this.detachListeners,
            this.restoreNativeCounters,this.disposeSensitivityEditor,this.disposeSliderPositions,this.restoreControlsBackground,this.disposeProfileTabsDonor])
         {
            try
            {
               cleanup();
            }
            catch(error:Error)
            {
               // A cleanup failure must not abort native window destruction
               // or prevent the next settings window from being initialized.
               trace("[nidin.control_settings] Settings cleanup failed: " + error.getStackTrace());
            }
         }
         // Cancel/revert belongs to the native settings model. Do not restore
         // providers, validate renderers or resize a list being destroyed.
         sensitivityEditor = null;
         sliderPositions = null;
         profileTabs = null;
         profileTabsDonor = null;
         controlsBackground = null;
         controlsBackgroundMask = null;
         controlsLayoutSnapshot = null;
         controlsSettings = null;
         commonKeysProvider = null;
         modeKeysProviders = null;
         profileKeys = null;
         profileChanges = null;
         profilesDirty = false;
         settingsWindow = null;
         hook = null;
      }

      private function cancelPendingTasks() : void
      {
         App.utils.scheduler.cancelTask(this.onSettingsWindowOpened);
         App.utils.scheduler.cancelTask(this.finishProfileTabsInstall);
         App.utils.scheduler.cancelTask(this.retryInstallProfileTabs);
         App.utils.scheduler.cancelTask(this.refreshNativeProvider);
         App.utils.scheduler.cancelTask(this.finishControlsLayoutAfterNativeValidation);
         App.utils.scheduler.cancelTask(this.refreshScrollBarAfterProviderChange);
      }

      private function detachListeners() : void
      {
         if(controlsSettings != null)
         {
            controlsSettings.removeEventListener(Event.ADDED,this.onNativeCounterAdded);
         }
         if(controlsSettings != null && controlsSettings.keys != null)
         {
            controlsSettings.keys.removeEventListener(ListEventEx.ITEM_TEXT_CHANGE,this.onKeysItemTextChangeHandler);
         }
         if(settingsWindow != null)
         {
            settingsWindow.removeEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE,this.handleSettingsWindowBeforeDispose);
            if(settingsWindow.applyBtn != null)
            {
               settingsWindow.applyBtn.removeEventListener(ButtonEvent.CLICK,this.onCommitClick);
               settingsWindow.applyBtn.removeEventListener(ButtonEvent.CLICK,this.onCommitFinished);
            }
            if(settingsWindow.submitBtn != null)
            {
               settingsWindow.submitBtn.removeEventListener(ButtonEvent.CLICK,this.onCommitClick);
               settingsWindow.submitBtn.removeEventListener(ButtonEvent.CLICK,this.onCommitFinished);
            }
            if(settingsWindow.view != null)
            {
               settingsWindow.view.removeEventListener(ViewStackEvent.VIEW_CHANGED,this.onViewStackEventHandler);
               settingsWindow.view.removeEventListener(ViewStackEvent.NEED_UPDATE,this.onViewStackEventHandler);
            }
         }
      }

      private function disposeSensitivityEditor() : void
      {
         if(sensitivityEditor != null)
         {
            sensitivityEditor.dispose();
            sensitivityEditor = null;
         }
      }

      private function disposeSliderPositions() : void
      {
         if(sliderPositions != null)
         {
            sliderPositions.dispose();
            sliderPositions = null;
         }
      }

      private function disposeProfileTabsDonor() : void
      {
         if(profileTabs != null)
         {
            profileTabs.removeEventListener(IndexEvent.INDEX_CHANGE,this.onProfileTabChanged);
            profileTabs = null;
         }
         if(profileTabsDonor != null)
         {
            if(profileTabsDonor.parent != null)
            {
               profileTabsDonor.parent.removeChild(profileTabsDonor);
            }
            // AimSettings is used only as a visual donor while the window is
            // open. Its base disposal still requires the data lifecycle that
            // creates headDependedControls. Complete it only after detaching,
            // so native aim events cannot reach the closing settings window.
            profileTabsDonor.visible = false;
            if(!profileTabsDonor.initialized)
            {
               profileTabsDonor.validateNow();
            }
            if(profileTabsDonor.headDependedControls == null)
            {
               var ownedProvider:IDataProvider = profileTabsDonor.tabs.dataProvider;
               try
               {
                  profileTabsDonor.update(new SettingsViewData("AimSettings",
                     SettingsConfigHelper.instance.getDataItem("AimSettings")));
               }
               finally
               {
                  // Native update attaches the shared aim-tabs provider.
                  // ButtonBar.dispose cleans its provider, so restore ours.
                  profileTabsDonor.tabs.dataProvider = ownedProvider;
               }
            }
            profileTabsDonor.dispose();
            profileTabsDonor = null;
         }
      }
   }
}
