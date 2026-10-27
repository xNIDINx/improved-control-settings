# -*- coding: utf-8 -*-

"""Persistent equipment-key profiles selected by the active battle mode."""

import BigWorld
import CommandMapping
import Keys
import Settings

from account_helpers.settings_core.options import KeyboardSetting
from constants import ARENA_BONUS_TYPE
from frameworks.wulf import WindowLayer
from gui.Scaleform.daapi.view.common.settings.SettingsWindow import SettingsWindow
from gui.Scaleform.framework import ScopeTemplates, ViewSettings, g_entitiesFactories
from gui.Scaleform.framework.entities.View import View
from gui.Scaleform.framework.managers.loaders import SFViewLoadParams
from gui.shared.utils import flashObject2Dict
from gui.shared.utils.key_mapping import BW_TO_SCALEFORM, SCALEFORM_TO_BW, getBigworldNameFromKey, getScaleformKey
from PlayerEvents import g_playerEvents
from helpers import dependency
from skeletons.gui.app_loader import GuiGlobalSpaceID, IAppLoader


MOD_ID = 'nidin.control_settings'
VIEW_ALIAS = MOD_ID + '.hook'
SWF_FILE = 'nidinControlSettings.swf'
LOAD_DELAY = 1.0
PREFERENCES_SECTION = 'nidinModeControlProfiles'
PREFERENCES_VERSION = 2
DIGITAL_SENSITIVITY_KEY = 'digitalSensitivityEnabled'
SLIDER_POSITIONS_KEY = 'sliderPositionsEnabled'
SENSITIVITY_MODE_KEY = 'sensitivityMode'

# Random battles always use common bindings, including with legacy preferences.
MODES = ('battleRoyale', 'comp7', 'frontline')
EQUIPMENT_COMMANDS = (
    'CMD_AMMO_CHOICE_1',
    'CMD_AMMO_CHOICE_2',
    'CMD_AMMO_CHOICE_3',
    'CMD_AMMO_CHOICE_4',
    'CMD_AMMO_CHOICE_5',
    'CMD_AMMO_CHOICE_6',
    'CMD_AMMO_CHOICE_7',
    'CMD_AMMO_CHOICE_8',
    'CMD_AMMO_CHOICE_9',
    'CMD_AMMO_CHOICE_0',
)
MODE_BY_BONUS_TYPE = {}
for _bonusType in ARENA_BONUS_TYPE.BATTLE_ROYALE_RANGE:
    MODE_BY_BONUS_TYPE[_bonusType] = 'battleRoyale'
MODE_BY_BONUS_TYPE[ARENA_BONUS_TYPE.COMP7] = 'comp7'
MODE_BY_BONUS_TYPE[ARENA_BONUS_TYPE.TOURNAMENT_COMP7] = 'comp7'
MODE_BY_BONUS_TYPE[ARENA_BONUS_TYPE.EPIC_BATTLE] = 'frontline'
MODE_BY_BONUS_TYPE[ARENA_BONUS_TYPE.EPIC_BATTLE_TRAINING] = 'frontline'

_loadCallback = None
_appLoader = None
_profiles = None
# The arena's selected mode and the mapping currently installed in the client
# are tracked separately: teardown may restore common keys before UI disposal.
_activeMode = None
_battleMode = None
_settingsWindows = set()
# Native equipment options share this common-key copy while battle keys remain
# live. Keep it until the last settings window is released, including on errors.
_settingsCommonBindings = None
_hookViewsByApp = {}
_modEnabled = True
_digitalSensitivityEnabled = True
_sliderPositionsEnabled = False
_modSettingsRegistered = False


def _log(message):
    print '[nidin.control_settings] %s' % message


def _readSensitivityMode(values):
    if SENSITIVITY_MODE_KEY in values:
        mode = values[SENSITIVITY_MODE_KEY]
        return mode if type(mode) in (int, long) and mode in (0, 1, 2) else 0
    # Migrate the old checkbox pair. An empty/conflicting pair uses the default.
    return int(values.get(DIGITAL_SENSITIVITY_KEY, True) is False and
               values.get(SLIDER_POSITIONS_KEY, False) is True)


def _onModSettingsChanged(linkage, values):
    global _digitalSensitivityEnabled, _sliderPositionsEnabled
    if linkage != MOD_ID or not isinstance(values, dict):
        return
    mode = _readSensitivityMode(values)
    _digitalSensitivityEnabled = mode == 0
    _sliderPositionsEnabled = mode == 1
    # Store one choice: neither an empty selection nor two active modes exist.
    values[SENSITIVITY_MODE_KEY] = mode
    values.pop(DIGITAL_SENSITIVITY_KEY, None)
    values.pop(SLIDER_POSITIONS_KEY, None)
    enabled = values.get('enabled', True)
    values['enabled'] = enabled if isinstance(enabled, bool) else True
    _setModEnabled(values['enabled'])
    # A sensitivity-mode change alone is read by the next settings window.


def _setModEnabled(enabled):
    global _modEnabled, _settingsCommonBindings
    if _modEnabled == enabled:
        return
    _modEnabled = enabled
    if not enabled:
        _settingsCommonBindings = None
    try:
        # Keep the arena identity while disabled so re-enabling can restore its
        # profile. _applyProfile itself enforces the master switch everywhere.
        _applyProfile(_battleMode)
    except Exception as error:
        _log('could not reconcile bindings after toggling the mod: %r' % error)
    for hook in tuple(_hookViewsByApp.values()):
        try:
            hook.setModEnabled(enabled)
        except Exception as error:
            _log('could not toggle settings UI: %r' % error)


def _registerModSettings():
    global _modSettingsRegistered
    if _modSettingsRegistered:
        return
    try:
        from gui.modsSettingsApi import g_modsSettingsApi, templates
    except ImportError:
        # Optional integration: without the settings menu the editor stays on.
        return
    try:
        template = {
            'modDisplayName': u'Улучшенные настройки управления',
            'settingsVersion': 7,
            'enabled': True,
            'column1': [templates.createRadioButtonGroup(
                u'Режим настройки чувствительности', SENSITIVITY_MODE_KEY,
                [u'Точная цифровая из preference',
                 u'Упрощённая от 0 до 100', u'Стандартный'], 0,
                tooltip=(u'{BODY}Точная настройка: поля под ползунками показывают значения '
                         u'чувствительности из настроек игры и позволяют вводить их вручную '
                         u'с шестью знаками после запятой.\n\n'
                         u'Упрощённая настройка: числа справа показывают положение ползунков '
                         u'от 0 до 100. Для изменения чувствительности перемещайте ползунок.{/BODY}'))],
            'column2': []
        }
        saved = g_modsSettingsApi.getModSettings(MOD_ID, template)
        if saved is None:
            previous = g_modsSettingsApi.getModSettings(MOD_ID, {'settingsVersion': 1})
            previous = dict(previous) if isinstance(previous, dict) else None
            saved = g_modsSettingsApi.setModTemplate(MOD_ID, template, _onModSettingsChanged)
            if saved is not None and previous is not None:
                # API 1.7.1 resets values on template upgrades. Migrate the old
                # pair before replacing it with a single native radio group.
                saved = dict(saved)
                saved[SENSITIVITY_MODE_KEY] = _readSensitivityMode(previous)
                saved['enabled'] = previous.get('enabled', True)
                _onModSettingsChanged(MOD_ID, saved)
                g_modsSettingsApi.updateModSettings(MOD_ID, saved)
                g_modsSettingsApi.saveState()
        else:
            g_modsSettingsApi.registerCallback(MOD_ID, _onModSettingsChanged)
        if saved is None:
            raise RuntimeError('ModsSettingsAPI rejected the settings template')
        _onModSettingsChanged(MOD_ID, saved)
        _modSettingsRegistered = True
    except Exception as error:
        # setModTemplate can fail after subscribing; avoid a duplicate on retry.
        try:
            g_modsSettingsApi.onSettingsChanged -= _onModSettingsChanged
        except Exception:
            pass
        _log('could not register the digital sensitivity option: %r' % error)


def _getPreferencesRoot():
    if Settings.g_instance is None or Settings.g_instance.userPrefs is None:
        return None
    preferences = Settings.g_instance.userPrefs
    if preferences.has_key(PREFERENCES_SECTION):
        return preferences[PREFERENCES_SECTION]
    return None


def _getProfiles():
    return _profiles if _profiles is not None else _loadProfiles()


def _loadProfiles():
    global _profiles
    if Settings.g_instance is None or Settings.g_instance.userPrefs is None or CommandMapping.g_instance is None:
        raise RuntimeError('settings are not ready')
    result = {}
    common = _getCommonBindings()
    root = _getPreferencesRoot()
    version = root.readInt('version', 1) if root is not None else PREFERENCES_VERSION
    needsSave = root is None or version != PREFERENCES_VERSION
    for mode in MODES:
        # Seed each mode once, then persist a complete independent snapshot.
        bindings = dict(common)
        modeSection = root[mode] if root is not None and root.has_key(mode) else None
        if modeSection is None:
            needsSave = True
        else:
            for command in EQUIPMENT_COMMANDS:
                if modeSection.has_key(command):
                    keyCode = modeSection.readInt(command, -1)
                    # Versions 0.7.0/0.7.1 received Scaleform codes from the UI.
                    if version == 1:
                        keyCode = SCALEFORM_TO_BW.get(keyCode, -1)
                    if keyCode in BW_TO_SCALEFORM:
                        bindings[command] = keyCode
                    else:
                        needsSave = True
                else:
                    needsSave = True
        result[mode] = bindings
    if needsSave:
        _writeProfiles(result)
    _profiles = result
    return result


def _normaliseProfiles(rawProfiles):
    rawProfiles = flashObject2Dict(rawProfiles)
    result = {}
    if not isinstance(rawProfiles, dict):
        raise ValueError('profiles must be an object')
    for mode in MODES:
        if mode not in rawProfiles:
            continue
        rawBindings = rawProfiles.get(mode)
        if not isinstance(rawBindings, dict):
            raise ValueError('invalid profile: %s' % mode)
        bindings = {}
        for command in EQUIPMENT_COMMANDS:
            if command not in rawBindings:
                raise ValueError('incomplete profile: %s/%s' % (mode, command))
            try:
                keyCode = int(rawBindings[command])
            except (TypeError, ValueError, OverflowError):
                raise ValueError('invalid key: %s/%s' % (mode, command))
            if keyCode not in SCALEFORM_TO_BW or keyCode != rawBindings[command]:
                raise ValueError('unknown Scaleform key: %r' % rawBindings[command])
            bindings[command] = SCALEFORM_TO_BW[keyCode]
        result[mode] = bindings
    if not result:
        raise ValueError('no mode bindings were received')
    return result


def _writeProfiles(profiles):
    if Settings.g_instance is None or Settings.g_instance.userPrefs is None:
        raise RuntimeError('preferences are not ready')
    preferences = Settings.g_instance.userPrefs
    preferences.deleteSection(PREFERENCES_SECTION)
    root = preferences.createSection(PREFERENCES_SECTION)
    root.writeInt('version', PREFERENCES_VERSION)
    for mode in MODES:
        bindings = profiles.get(mode)
        if not bindings:
            continue
        modeSection = root.createSection(mode)
        for command in EQUIPMENT_COMMANDS:
            if command in bindings:
                modeSection.writeInt(command, bindings[command])
    Settings.g_instance.save()


def _saveProfiles(rawProfiles):
    global _profiles
    if not _modEnabled:
        return False
    try:
        changes = _normaliseProfiles(rawProfiles)
        stored = _getProfiles()
        profiles = dict((mode, dict(bindings)) for mode, bindings in stored.iteritems())
        profiles.update(changes)
        _writeProfiles(profiles)
        _profiles = profiles
        if _activeMode in changes:
            _applyProfile(_activeMode)
        _log('saved profiles: %s' % ', '.join(sorted(changes)))
        return True
    except Exception as error:
        _log('profiles were not saved: %r' % error)
        return False


def _getCommonBindings():
    # Read persistent common bindings, never the temporary battle mapping.
    mapping = CommandMapping.g_instance
    defaults = mapping.getDefaults()
    preferences = Settings.g_instance.userPrefs
    section = preferences[Settings.KEY_COMMAND_MAPPING] if preferences.has_key(Settings.KEY_COMMAND_MAPPING) else None
    result = {}
    for command in EQUIPMENT_COMMANDS:
        keyCode = defaults.get(mapping.getCommand(command), Keys.KEY_NONE)
        if section is not None and section.has_key(command):
            keyCode = getattr(Keys, section[command].readString('fireKey'), Keys.KEY_NONE)
        result[command] = keyCode
    return result


def _setEquipmentBindings(bindings):
    mapping = CommandMapping.g_instance
    for command in EQUIPMENT_COMMANDS:
        mapping.remove(command)
        # Keep KEY_NONE explicitly, as the native settings code does. An absent
        # command would be displayed as its default key on reopening settings.
        if not mapping.add(command, getBigworldNameFromKey(bindings[command])):
            raise ValueError('could not bind %s to %r' % (command, bindings[command]))


def _notifyMappingChanged():
    try:
        CommandMapping.g_instance.onMappingChanged()
    except Exception as error:
        _log('could not notify mapping listeners: %r' % error)


def _restoreCommonMapping(notify=True):
    global _activeMode
    if CommandMapping.g_instance is None or _activeMode is None:
        return
    _setEquipmentBindings(_getCommonBindings())
    _activeMode = None
    if notify:
        _notifyMappingChanged()
    _log('restored common equipment bindings')


def _applyProfile(mode):
    global _activeMode, _settingsCommonBindings
    if CommandMapping.g_instance is None:
        _log('profile was not applied: command mapping is not ready')
        return
    if not _modEnabled or mode not in MODES:
        _restoreCommonMapping()
        _log('using common equipment bindings')
        return
    if _settingsWindows and _settingsCommonBindings is None:
        _settingsCommonBindings = _getCommonBindings()
    profiles = _getProfiles()
    if _activeMode == mode and all(CommandMapping.g_instance.get(command) == profiles[mode][command]
                                   for command in EQUIPMENT_COMMANDS):
        return
    _activeMode = mode
    _setEquipmentBindings(profiles[mode])
    _notifyMappingChanged()
    _log('applied equipment profile: %s' % mode)


def _onAvatarBecomePlayer():
    global _battleMode
    try:
        player = BigWorld.player()
        bonusType = getattr(player, 'arenaBonusType', ARENA_BONUS_TYPE.UNKNOWN)
        _battleMode = MODE_BY_BONUS_TYPE.get(bonusType)
        _applyProfile(_battleMode)
    except Exception as error:
        _log('could not apply battle profile: %r' % error)
        _restoreCommonMapping()


def _onAvatarBecomeNonPlayer():
    global _battleMode
    _battleMode = None
    try:
        # Battle consumers may already have disposed their equipment model.
        _restoreCommonMapping(notify=False)
    except Exception as error:
        _log('could not restore common profile: %r' % error)


class NidinControlSettingsHook(View):

    def _populate(self):
        super(NidinControlSettingsHook, self)._populate()
        _hookViewsByApp[id(self.app)] = self
        _log('UI hook loaded for the current Scaleform app')

    def _dispose(self):
        appKey = id(self.app)
        if _hookViewsByApp.get(appKey) is self:
            del _hookViewsByApp[appKey]
        super(NidinControlSettingsHook, self)._dispose()

    def refreshSettings(self):
        if self._isDAAPIInited():
            self.flashObject.as_refreshSettings()

    def setModEnabled(self, enabled):
        if self._isDAAPIInited():
            self.flashObject.as_setModEnabled(enabled)

    def isModEnabled(self):
        return _modEnabled

    def onBridgeReady(self):
        # Flash has moved the bridge out of its Wulf wrapper. Hiding alone
        # leaves a LOADED OVERLAY window that blocks notification commands.
        # Move only that empty Wulf window; the Scaleform view must keep its
        # multi-view OVERLAY registration and container ownership.
        window = self.getParentWindow()
        if window is not None:
            if not window.isHidden():
                window.hide()
            if window.layer != WindowLayer.HIDDEN_SERVICE_LAYOUT:
                window.setLayer(WindowLayer.HIDDEN_SERVICE_LAYOUT)

    def getProfiles(self):
        if not _modEnabled:
            return {}
        profiles = _getProfiles()
        return dict((mode, dict((command, getScaleformKey(key)) for command, key in bindings.iteritems()))
                    for mode, bindings in profiles.iteritems())

    def saveProfiles(self, profiles):
        return _saveProfiles(profiles)

    def isDigitalSensitivityEnabled(self):
        return _modEnabled and _digitalSensitivityEnabled

    def isSliderPositionsEnabled(self):
        return _modEnabled and _sliderPositionsEnabled and not _digitalSensitivityEnabled


def _registerView():
    if g_entitiesFactories.getSettings(VIEW_ALIAS) is not None:
        return
    # SERVICE_LAYOUT is a SingleViewContainer: loading this hook there would
    # evict other mods, including WotStat Widgets. OVERLAY supports multiple
    # independent views in both applications. onBridgeReady hides and moves
    # only the empty Wulf wrapper, without changing Scaleform container routing.
    settings = ViewSettings(
        VIEW_ALIAS, NidinControlSettingsHook, SWF_FILE,
        WindowLayer.OVERLAY, None, ScopeTemplates.GLOBAL_SCOPE, False,
        canDrag=False, canClose=False, isModal=False, isCentered=False)
    g_entitiesFactories.addSettings(settings)


def _ensureHookForApp(app):
    if app is None or id(app) in _hookViewsByApp:
        return
    try:
        app.loadView(SFViewLoadParams(VIEW_ALIAS))
        _log('UI hook load requested for the current Scaleform app')
    except Exception as error:
        _log('could not load UI hook: %r' % error)


def _onGUIInitialized():
    _registerModSettings()
    _ensureHookForApp(_appLoader.getDefLobbyApp())
    _ensureHookForApp(_appLoader.getDefBattleApp())


def _loadView():
    global _loadCallback
    _loadCallback = None
    _onGUIInitialized()


def _onGUISpaceEntered(spaceID):
    global _loadCallback
    if spaceID == GuiGlobalSpaceID.BATTLE:
        # Reconcile once after battle GUI initialization, not only at Avatar
        # creation while the lobby is still being torn down.
        _onAvatarBecomePlayer()
        _onGUIInitialized()
        return
    if spaceID != GuiGlobalSpaceID.LOBBY:
        return
    # The lobby always uses the real global command mapping. This is also a
    # safety net for disconnects where the normal Avatar teardown is skipped.
    _onAvatarBecomeNonPlayer()
    if _modEnabled and _profiles is None:
        try:
            _loadProfiles()
        except Exception as error:
            _log('could not initialise profiles: %r' % error)
    if _loadCallback is not None:
        BigWorld.cancelCallback(_loadCallback)
    _loadCallback = BigWorld.callback(LOAD_DELAY, _loadView)


_originalMappingSave = CommandMapping.CommandMapping.save
_originalSettingsPopulate = SettingsWindow._populate
_originalSettingsDispose = SettingsWindow._dispose
_originalSettingsUpdate = SettingsWindow._update
_originalKeyboardGet = KeyboardSetting.getCurrentMapping
_originalKeyboardSet = KeyboardSetting.setSystemValue


def _releaseSettingsWindow(window):
    global _settingsCommonBindings
    _settingsWindows.discard(id(window))
    if not _settingsWindows:
        _settingsCommonBindings = None


def _settingsPopulate(window, *args, **kwargs):
    global _settingsCommonBindings
    if _modEnabled and not _settingsWindows and _activeMode is not None:
        # Native keyboard options edit common values without replacing the
        # live battle mapping or notifying the equipment panel of a switch.
        _settingsCommonBindings = _getCommonBindings()
    _settingsWindows.add(id(window))
    _ensureHookForApp(window.app)
    try:
        return _originalSettingsPopulate(window, *args, **kwargs)
    except Exception:
        _releaseSettingsWindow(window)
        raise


def _settingsDispose(window, *args, **kwargs):
    try:
        return _originalSettingsDispose(window, *args, **kwargs)
    finally:
        _releaseSettingsWindow(window)
        _applyProfile(_battleMode)


def _settingsUpdate(window, *args, **kwargs):
    result = _originalSettingsUpdate(window, *args, **kwargs)
    hook = _hookViewsByApp.get(id(window.app))
    if _modEnabled and hook is not None:
        try:
            hook.refreshSettings()
        except Exception as error:
            _log('could not refresh profile tabs: %r' % error)
    return result


def _saveCommonCommandMapping(mapping, *args, **kwargs):
    if not _modEnabled or mapping is not CommandMapping.g_instance or (_activeMode is None and _settingsCommonBindings is None):
        return _originalMappingSave(mapping, *args, **kwargs)
    # Persist the common values edited by native KeyboardSetting, or the
    # stored common mapping for a background save outside settings.
    active = dict((command, mapping.get(command)) for command in EQUIPMENT_COMMANDS)
    common = _settingsCommonBindings if _settingsCommonBindings is not None else _getCommonBindings()
    _setEquipmentBindings(common)
    try:
        return _originalMappingSave(mapping, *args, **kwargs)
    finally:
        if _activeMode is not None:
            _setEquipmentBindings(active)


def _getKeyboardMapping(setting, *args, **kwargs):
    if _modEnabled and _settingsCommonBindings is not None and setting.cmd in EQUIPMENT_COMMANDS:
        return _settingsCommonBindings[setting.cmd]
    return _originalKeyboardGet(setting, *args, **kwargs)


def _setKeyboardMapping(setting, value):
    if _modEnabled and _settingsCommonBindings is not None and setting.cmd in EQUIPMENT_COMMANDS:
        _settingsCommonBindings[setting.cmd] = Keys.KEY_NONE if value is None else SCALEFORM_TO_BW[value]
        if _activeMode is not None:
            return
    return _originalKeyboardSet(setting, value)


CommandMapping.CommandMapping.save = _saveCommonCommandMapping
KeyboardSetting.getCurrentMapping = _getKeyboardMapping
KeyboardSetting.setSystemValue = _setKeyboardMapping
SettingsWindow._populate = _settingsPopulate
SettingsWindow._dispose = _settingsDispose
SettingsWindow._update = _settingsUpdate
_registerModSettings()
_registerView()
_appLoader = dependency.instance(IAppLoader)
_appLoader.onGUISpaceEntered += _onGUISpaceEntered
_appLoader.onGUIInitialized += _onGUIInitialized
g_playerEvents.onAvatarBecomePlayer += _onAvatarBecomePlayer
g_playerEvents.onAvatarBecomeNonPlayer += _onAvatarBecomeNonPlayer
_log('registered')
