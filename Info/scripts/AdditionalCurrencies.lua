--
-- AdditionalCurrencies
--
-- @author Rockstar
-- @date 10/02/2021
--

--
--	@fs22 22/11/2021
--

--
--	@fs25 30/11/2024
--


AdditionalCurrencies = {
	MOD_NAME = g_currentModName,
	MOD_SETTINGS_DIRECTORY = g_currentModSettingsDirectory,
	BASE_CONFIG_FILENAME = g_currentModDirectory .. "currencies.xml",
	CUSTOM_CONFIG_FILENAME = g_currentModSettingsDirectory .. "additionalCurrencies.xml",
	SAVE_PATH = g_currentModSettingsDirectory .. "settings.xml"
}

local g_env_i18n = getmetatable(g_i18n).__index

function AdditionalCurrencies:new(missionInfo)
	createFolder(AdditionalCurrencies.MOD_SETTINGS_DIRECTORY)

	local configFilename = AdditionalCurrencies.CUSTOM_CONFIG_FILENAME

	if not fileExists(configFilename) then
		configFilename = AdditionalCurrencies.BASE_CONFIG_FILENAME
	end

	self.globalTexts = {"button_borrow5000", "button_repay5000", "helpLine_Economy_MakingMoney_FinanceScreen", "hint_17"}

	local gameInfoDisplay = g_currentMission.hud.gameInfoDisplay

	self.defaultMaxDisplayValue = I18N.MONEY_MAX_DISPLAY_VALUE
	self.defaultMoneyBoxWidth = gameInfoDisplay.moneyBgScale.width
	self.defaultMoneyTextWidth = getTextWidth(gameInfoDisplay.moneyTextSize, g_i18n:formatNumber(self.defaultMaxDisplayValue))

	local multiMoneyUnit = g_inGameMenu.multiMoneyUnit
	local currencies, texts = self:loadCurrencyConfigsFromXMLFile(configFilename, multiMoneyUnit.texts)

	self.currencies = currencies

	local pageSettings = g_inGameMenu.pageSettings

	pageSettings.optionMapping[multiMoneyUnit] = nil

	AdditionalCurrenciesUtil.appendedFunction(pageSettings, "onFrameOpen", self, "pageSettings_onFrameOpen")
	AdditionalCurrenciesUtil.appendedFunction(pageSettings, "onFrameClose", self, "pageSettings_onFrameClose")
	AdditionalCurrenciesUtil.appendedFunction(FSCareerMissionInfo, "saveToXMLFile", self, "missionInfo_saveToXMLFile")
	AdditionalCurrenciesUtil.overwrittenFunction(g_env_i18n, "getCurrencySymbol", self, "i18n_getCurrencySymbol", false)
	AdditionalCurrenciesUtil.overwrittenFunction(g_env_i18n, "formatMoney", self, "i18n_formatMoney", false)
	AdditionalCurrenciesUtil.overwrittenFunction(gameInfoDisplay, "draw", self, "gameInfoDisplay_draw", false)

	local state, converter = self:loadCurrencySettingsFromXMLFile(g_gameSettings:getValue(GameSettings.SETTING.MONEY_UNIT), true)

	multiMoneyUnit.onClickCallback = AdditionalCurrenciesUtil.makeCallback(self, self.onClickMoneyUnit)
	multiMoneyUnit:setState(state)
	multiMoneyUnit:setTexts(texts)

	self.checkCurrConv = self:createCurrConvElement(pageSettings)
	self.checkCurrConv:setIsChecked(converter, true)

	self.converter = converter
	self:setMoneyUnit(state)

	local accountBalance = missionInfo.money or missionInfo.initialMoney

	if accountBalance ~= nil then
		g_mpLoadingScreen.balanceText:setText(g_i18n:formatMoney(accountBalance, 0, true, true))
	end
end

function AdditionalCurrencies:loadCurrencyConfigsFromXMLFile(xmlFilename, defaultTexts)
	local currencies = {}
	local texts = defaultTexts
	local xmlFile = XMLFile.loadIfExists("currenciesXML", xmlFilename)

	if xmlFile ~= nil then
		currencies[1] = {
			prefix = false,
			factor = xmlFile:getFloat("currencies#euroFactor", 1),
			maxDisplayValue = self.defaultMaxDisplayValue,
			isDefault = true
		}
		currencies[2] = {
			prefix = true,
			factor = xmlFile:getFloat("currencies#dolarFactor", 1.34),
			maxDisplayValue = self.defaultMaxDisplayValue,
			isDefault = true
		}
		currencies[3] = {
			prefix = true,
			factor = xmlFile:getFloat("currencies#poundFactor", 0.79),
			maxDisplayValue = self.defaultMaxDisplayValue,
			isDefault = true
		}

		local i = 0

		while true do
			local key = string.format("currencies.currency(%d)", i)

			if not xmlFile:hasProperty(key) then
				break
			end

			local unit = xmlFile:getI18NValue(key .. "#text", "", AdditionalCurrencies.MOD_NAME, true)
			local unitShort = xmlFile:getI18NValue(key .. "#symbol", "", AdditionalCurrencies.MOD_NAME, true)
			local prefix = xmlFile:getBool(key .. "#prefixSymbol", true)
			local factor = xmlFile:getFloat(key .. "#factor", 1)
			local maxDisplayValue = xmlFile:getString(key .. "#maxDisplayValue", self.defaultMaxDisplayValue)
			local iconSymbol = xmlFile:getI18NValue(key .. "#iconSymbol", unitShort, AdditionalCurrencies.MOD_NAME, true)

			table.insert(texts, unit)
			table.insert(currencies,
			{
				unit = unit,
				unitShort = unitShort,
				prefix = prefix,
				factor = factor,
				maxDisplayValue = tonumber(maxDisplayValue),
				iconSymbol = iconSymbol .. " ",
				isDefault = false
			})

			i = i + 1
		end

		xmlFile:delete()
	end

	return currencies, texts
end

function AdditionalCurrencies:loadCurrencySettingsFromXMLFile(state, converter)
	local xmlFile = XMLFile.loadIfExists("currencySettingsXML", AdditionalCurrencies.SAVE_PATH)

	if xmlFile ~= nil then
		local currency = xmlFile:getInt("settings.currency", state)

		if currency <= #self.currencies then
			state = currency
		end

		converter = xmlFile:getBool("settings.converter", converter)

		xmlFile:delete()
	end

	return state, converter
end

function AdditionalCurrencies:saveCurrencySettingsToXMLFile()
	local xmlFile = XMLFile.create("currencySettingsXML", AdditionalCurrencies.SAVE_PATH, "settings")

	if xmlFile ~= nil then
		xmlFile:setInt("settings.currency", self.state)
		xmlFile:setBool("settings.converter", self.converter)
		xmlFile:save()
		xmlFile:delete()
	end
end

function AdditionalCurrencies:createCurrConvElement(settingsPage)
	local checkMilesContainer = settingsPage.checkUseMiles.parent
	local checkCurrencyContainer = checkMilesContainer:clone(settingsPage)
	local checkCurrencyMto = checkCurrencyContainer.elements[1]
	local checkCurrencyTooltip = checkCurrencyMto.elements[1]
	local checkCurrencyText = checkCurrencyContainer.elements[2]

	checkCurrencyMto:setTexts({g_i18n:getText("ui_off"), g_i18n:getText("ui_on")})
	checkCurrencyMto.id = "checkCurrencyConverter"
	checkCurrencyMto.focusId = nil
	checkCurrencyMto.onClickCallback = AdditionalCurrenciesUtil.makeCallback(self, self.onClickCurrConv)
	checkCurrencyTooltip:setText(g_i18n:getText("toolTip_currencyConverter"))
	checkCurrencyText:setText(g_i18n:getText("setting_currencyConverter"))

	local parent = checkMilesContainer.parent

	checkCurrencyContainer.parent:removeElement(checkCurrencyContainer)
	table.insert(parent.elements, table.find(parent.elements, checkMilesContainer), checkCurrencyContainer)
	checkCurrencyContainer.parent = parent

	local currentGui = FocusManager.currentGui

	FocusManager:setGui("ingameMenuSettings")
	FocusManager:loadElementFromCustomValues(checkCurrencyMto)
	FocusManager:setGui(currentGui)

	return checkCurrencyMto
end

function AdditionalCurrencies:getCurrency()
	return self.currencies[self.state]
end

function AdditionalCurrencies:updateTextsAndMoneyBoxWidth()
	for _, name in pairs(self.globalTexts) do
		g_env_i18n:setText(name, string.format(g_i18n:getText("g_" .. name), g_i18n:formatMoney(5000)))
	end

	local maxDisplayValue = self.defaultMaxDisplayValue

	if self.converter then
		maxDisplayValue = self:getCurrency().maxDisplayValue
	end

	if maxDisplayValue ~= nil and maxDisplayValue ~= I18N.MONEY_MAX_DISPLAY_VALUE then
		I18N.MONEY_MAX_DISPLAY_VALUE, I18N.MONEY_MIN_DISPLAY_VALUE = maxDisplayValue, -maxDisplayValue

		local gameInfoDisplay = g_currentMission.hud.gameInfoDisplay
		local maxMoneyTextWidth = getTextWidth(gameInfoDisplay.moneyTextSize, g_i18n:formatNumber(maxDisplayValue))
		local extraWidth = maxMoneyTextWidth - self.defaultMoneyTextWidth

		gameInfoDisplay.moneyBgScale:setDimension(self.defaultMoneyBoxWidth + extraWidth, nil)
	end
end

function AdditionalCurrencies:setMoneyUnit(state)
	self.state = state

	g_env_i18n:setMoneyUnit(state)
	g_currentMission:setMoneyUnit(state)

	self:updateTextsAndMoneyBoxWidth()
	self.checkCurrConv:setDisabled(self:getCurrency().factor == 1)
end

function AdditionalCurrencies:i18n_getCurrencySymbol(i18n, superFunc, useShort)
	local currency = self:getCurrency()

	if currency.isDefault then
		return superFunc(i18n, useShort)
	end

	local text = currency.unit

	if useShort then
		text = currency.unitShort
	end

	return text
end

function AdditionalCurrencies:i18n_formatMoney(i18n, superFunc, number, precision, addCurrency, prefixCurrencySymbol)
	local currency = self:getCurrency()

	if addCurrency == nil or addCurrency then
		prefixCurrencySymbol = currency.prefix
	end

	if self.converter and currency.factor ~= 1 then
		number = number * currency.factor
	end

	return superFunc(i18n, number, precision, addCurrency, prefixCurrencySymbol)
end

function AdditionalCurrencies:pageSettings_onFrameOpen(pageSettings)
	self.checkCurrConv:setDisabled(self:getCurrency().factor == 1)
end

function AdditionalCurrencies:pageSettings_onFrameClose(pageSettings)
	self:saveCurrencySettingsToXMLFile()
end

function AdditionalCurrencies:missionInfo_saveToXMLFile(missionInfo)
	self:saveCurrencySettingsToXMLFile()
end

function AdditionalCurrencies:gameInfoDisplay_draw(gameInfoDisplay, superFunc, ...)
	local getCurrencySymbol_old  = g_env_i18n.getCurrencySymbol

	g_env_i18n.getCurrencySymbol = function(...)
		local currency = self:getCurrency()

		if currency.isDefault then
			return getCurrencySymbol_old(...) .. " "
		end

		return currency.iconSymbol
	end

	local retValue = superFunc(gameInfoDisplay, ...)

	g_env_i18n.getCurrencySymbol = getCurrencySymbol_old

	return retValue
end

function AdditionalCurrencies:onClickMoneyUnit(moneyUnitElement, state, optionElement)
	self:setMoneyUnit(state)
end

function AdditionalCurrencies:onClickCurrConv(currConvElement, state)
	self.converter = state == CheckedOptionElement.STATE_CHECKED
	self:updateTextsAndMoneyBoxWidth()
end

Mission00.setMissionInfo = Utils.prependedFunction(Mission00.setMissionInfo, function(mission00, missionInfo, missionDynamicInfo)
	AdditionalCurrencies:new(missionInfo)
end)