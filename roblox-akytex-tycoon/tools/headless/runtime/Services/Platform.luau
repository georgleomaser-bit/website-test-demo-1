--!nocheck
-- =====================================================================
--  Headless-Harness · Plattform-Services
--  MarketplaceService (ProcessReceipt, Prompt*/…Finished, UserOwnsGamePassAsync, PlayerOwnsAsset, GetProductInfo*,
--  GetDeveloperProductsAsync, Abo-Status), PolicyService, BadgeService, GroupService, SocialService,
--  ExperienceNotificationService, AvatarEditorService, AssetService, VoiceChatService, LocalizationService
--  (+Translator), AnalyticsService (Argumenttypen wie Roblox' Reflection-Umwandlung, sonst no-op), HttpService
--  (JSON wie Roblox, GenerateGUID, UrlEncode, HTTP-Anfragen -> "Http requests are not enabled").
--
--  Harness-API (R.Svc.Market):
--    Mk.ownedPasses[userId][passId] = true      Gamepass-Besitz (UserOwnsGamePassAsync)
--    Mk.ownedAssets[userId][assetId] = true
--    Mk.subscriptions[userId][subId] = true
--    Mk.purchase(game, player, productId, purchaseId?) -> Entscheidung (Enum.ProductPurchaseDecision) | nil, Fehler
--    Mk.prompts  Liste aller Kaufaufforderungen { kind, player, id, ctx, t }
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format

	local Mk = {}
	Svc.Market = Mk
	Mk.ownedPasses = {}
	Mk.ownedAssets = {}
	Mk.subscriptions = {}
	Mk.prompts = {}
	Mk.receipts = {}

	-- Reflection-Umwandlung wie Roblox (Strings <-> Zahlen, Enums aus Name/Zahl)
	local function castString(v, n, fname)
		if type(v) == "string" then
			return v
		elseif type(v) == "number" then
			return tostring(v)
		end
		if v == nil then
			Util.missingArg(n)
		end
		Util.badArg(n, fname, "string", v)
	end
	local function castNumber(v, n, fname)
		if v == nil then
			Util.missingArg(n)
		end
		return Util.checkNumber(v, n, fname)
	end
	local function castEnum(v, enumName, n, fname)
		local it = Enum.coerce(v, enumName)
		if it == nil then
			if v == nil then
				Util.missingArg(n)
			end
			Util.badArg(n, fname, "Enum." .. enumName, v)
		end
		return it
	end
	local function castPlayer(v, n, fname)
		local M = Inst.meta(v)
		if M == nil or not M.cls.isA.Player then
			if v == nil then
				Util.missingArg(n)
			end
			raise("Unable to cast value to Object")
		end
		return v
	end
	local function castDict(v, n, fname)
		if v == nil then
			return nil
		end
		if type(v) ~= "table" then
			raise("Unable to cast to Dictionary")
		end
		return v
	end
	Svc.cast = { string = castString, number = castNumber, enum = castEnum, player = castPlayer, dict = castDict }

	local function serverPlayer(p)
		if Svc.Net and Svc.Net.serverInstanceOf then
			return Svc.Net.serverInstanceOf(p) or p
		end
		return p
	end
	local function userIdOf(p)
		return getmt(p).props.UserId or 0
	end

	-- =================================================================================================
	--  MarketplaceService
	-- =================================================================================================
	local function mpsOf(game)
		return game and Inst.findServiceRaw(game, "MarketplaceService")
	end
	-- Prompt schließt nach 0,5 s ohne Kauf (Spieler bricht ab) -> …Finished auf Server und dem Client des Spielers
	local function promptClosed(self, player, kind, id, eventName, argsFn)
		local ctx = Svc.ctxOf(self)
		Mk.prompts[#Mk.prompts + 1] = { kind = kind, player = player, id = id, ctx = ctx.name, t = Sched.now }
		local sp = serverPlayer(player)
		Sched.addTimer(Sched.now + 0.5, function()
			for _, g in Svc.games do
				local c = g.ctx
				if not c.closed then
					local mps = mpsOf(g.game)
					local target
					if c.isClient then
						if Svc.Net and Svc.Net.clientInstanceOf then
							target = Svc.Net.clientInstanceOf(c, sp)
						end
						if target ~= nil and getmt(g.game).ext.localPlayer ~= target then
							target = nil
						end
					else
						target = sp
					end
					if mps and target then
						Inst.fire(mps, eventName, argsFn(target))
					end
				end
			end
		end)
	end

	local MPS = {}
	function MPS.PromptProductPurchase(self, player, productId, equip, currency)
		Inst.checkSelf(self, "PromptProductPurchase")
		castPlayer(player, 1, "PromptProductPurchase")
		productId = castNumber(productId, 2, "PromptProductPurchase")
		promptClosed(self, player, "Product", productId, "PromptProductPurchaseFinished", function(p)
			return userIdOf(p), productId, false
		end)
	end
	function MPS.PromptGamePassPurchase(self, player, passId)
		Inst.checkSelf(self, "PromptGamePassPurchase")
		castPlayer(player, 1, "PromptGamePassPurchase")
		passId = castNumber(passId, 2, "PromptGamePassPurchase")
		promptClosed(self, player, "GamePass", passId, "PromptGamePassPurchaseFinished", function(p)
			return p, passId, false
		end)
	end
	function MPS.PromptPurchase(self, player, assetId, equip, currency)
		Inst.checkSelf(self, "PromptPurchase")
		castPlayer(player, 1, "PromptPurchase")
		assetId = castNumber(assetId, 2, "PromptPurchase")
		promptClosed(self, player, "Asset", assetId, "PromptPurchaseFinished", function(p)
			return p, assetId, false
		end)
	end
	function MPS.PromptBundlePurchase(self, player, bundleId)
		Inst.checkSelf(self, "PromptBundlePurchase")
		castPlayer(player, 1, "PromptBundlePurchase")
		bundleId = castNumber(bundleId, 2, "PromptBundlePurchase")
		promptClosed(self, player, "Bundle", bundleId, "PromptBundlePurchaseFinished", function(p)
			return p, bundleId, false
		end)
	end
	function MPS.PromptPremiumPurchase(self, player)
		Inst.checkSelf(self, "PromptPremiumPurchase")
		castPlayer(player, 1, "PromptPremiumPurchase")
		promptClosed(self, player, "Premium", 0, "PromptPremiumPurchaseFinished", function()
			return
		end)
	end
	function MPS.PromptSubscriptionPurchase(self, player, subId)
		Inst.checkSelf(self, "PromptSubscriptionPurchase")
		castPlayer(player, 1, "PromptSubscriptionPurchase")
		subId = castString(subId, 2, "PromptSubscriptionPurchase")
		promptClosed(self, player, "Subscription", subId, "PromptSubscriptionPurchaseFinished", function(p)
			return p, subId, false
		end)
	end
	function MPS.UserOwnsGamePassAsync(self, userId, passId)
		Inst.checkSelf(self, "UserOwnsGamePassAsync")
		userId = castNumber(userId, 1, "UserOwnsGamePassAsync")
		passId = castNumber(passId, 2, "UserOwnsGamePassAsync")
		Svc.latency(0.1)
		local t = Mk.ownedPasses[userId]
		return t ~= nil and t[passId] == true
	end
	function MPS.PlayerOwnsAsset(self, player, assetId)
		Inst.checkSelf(self, "PlayerOwnsAsset")
		castPlayer(player, 1, "PlayerOwnsAsset")
		assetId = castNumber(assetId, 2, "PlayerOwnsAsset")
		Svc.latency(0.1)
		local t = Mk.ownedAssets[userIdOf(player)]
		return t ~= nil and t[assetId] == true
	end
	MPS.PlayerOwnsAssetAsync = MPS.PlayerOwnsAsset
	function MPS.PlayerOwnsBundle(self, player, bundleId)
		Inst.checkSelf(self, "PlayerOwnsBundle")
		castPlayer(player, 1, "PlayerOwnsBundle")
		castNumber(bundleId, 2, "PlayerOwnsBundle")
		Svc.latency(0.1)
		return false
	end
	MPS.PlayerOwnsBundleAsync = MPS.PlayerOwnsBundle
	local function productInfo(id, infoType)
		local t = infoType and infoType.Name or "Asset"
		local info = {
			Name = fmt("%s %d", t, id),
			Description = "",
			PriceInRobux = 100,
			IconImageAssetId = 0,
			Created = "2026-01-01T00:00:00Z",
			Updated = "2026-01-01T00:00:00Z",
			IsForSale = true,
			IsPublicDomain = false,
			IsLimited = false,
			IsLimitedUnique = false,
			Remaining = nil,
			Sales = 0,
			MinimumMembershipLevel = 0,
			ContentRatingTypeId = 0,
			Creator = { Name = "AkytexStudio", Id = 1, CreatorType = "User", CreatorTargetId = 1, HasVerifiedBadge = false },
		}
		if t == "Product" then
			info.ProductId = id
		elseif t == "GamePass" then
			info.TargetId = id
			info.ProductType = "Game Pass"
		else
			info.AssetId = id
			info.AssetTypeId = 1
		end
		return info
	end
	function MPS.GetProductInfo(self, assetId, infoType)
		Inst.checkSelf(self, "GetProductInfo")
		assetId = castNumber(assetId, 1, "GetProductInfo")
		local it = infoType ~= nil and castEnum(infoType, "InfoType", 2, "GetProductInfo") or Enum.item("InfoType", "Asset")
		Svc.latency(0.1)
		if assetId <= 0 then
			raise("MarketplaceService:getProductInfo() failed because HTTP 400 (Bad Request)")
		end
		return productInfo(assetId, it)
	end
	MPS.GetProductInfoAsync = MPS.GetProductInfo
	function MPS.GetDeveloperProductsAsync(self)
		Inst.checkSelf(self, "GetDeveloperProductsAsync")
		Svc.latency(0.1)
		local list = {}
		for _, id in Mk.developerProducts or {} do
			local inf = productInfo(id, Enum.item("InfoType", "Product"))
			list[#list + 1] = {
				ProductId = id,
				DeveloperProductId = id,
				Name = inf.Name,
				Description = "",
				PriceInRobux = inf.PriceInRobux,
				IconImageAssetId = 0,
			}
		end
		return Svc.newPages("StandardPages", { list })
	end
	local function checkSubId(id, n, fname)
		id = castString(id, n, fname)
		if not string.match(id, "^EXP%-%d+$") then
			raise(fmt("%s: invalid subscription id '%s'", fname, id))
		end
		return id
	end
	function MPS.GetUserSubscriptionStatusAsync(self, player, subId)
		Inst.checkSelf(self, "GetUserSubscriptionStatusAsync")
		castPlayer(player, 1, "GetUserSubscriptionStatusAsync")
		subId = checkSubId(subId, 2, "GetUserSubscriptionStatusAsync")
		if Svc.ctxOf(self).isClient then
			raise("GetUserSubscriptionStatusAsync can only be called from the server")
		end
		Svc.latency(0.1)
		local t = Mk.subscriptions[userIdOf(player)]
		local on = t ~= nil and t[subId] == true
		return { IsSubscribed = on, IsRenewing = on }
	end
	function MPS.GetSubscriptionProductInfoAsync(self, subId)
		Inst.checkSelf(self, "GetSubscriptionProductInfoAsync")
		subId = checkSubId(subId, 1, "GetSubscriptionProductInfoAsync")
		Svc.latency(0.1)
		return {
			Name = "Abo " .. subId,
			Description = "",
			IconImageAssetId = 0,
			SubscriptionPeriod = Enum.item("SubscriptionPeriod", "Month"),
			DisplayPrice = "$4.99",
			DisplaySubscriptionPeriod = "month",
			PriceTier = 499,
			IsForSale = true,
		}
	end
	function MPS.GetUserSubscriptionPaymentHistoryAsync(self, player, subId)
		Inst.checkSelf(self, "GetUserSubscriptionPaymentHistoryAsync")
		Svc.latency(0.1)
		return {}
	end
	Inst.registerService("MarketplaceService", { methods = MPS })

	--- Harness: Kauf eines Developer-Products simulieren (ruft ProcessReceipt auf dem Server; darf yielden)
	function Mk.purchase(game, player, productId, purchaseId)
		local mps = mpsOf(game)
		local cb = mps and Inst.callback(mps, "ProcessReceipt")
		if cb == nil then
			return nil, "ProcessReceipt ist nicht gesetzt"
		end
		Mk.receiptSeq = (Mk.receiptSeq or 0) + 1
		local info = {
			PurchaseId = purchaseId or fmt("harness-%d-%d", productId, Mk.receiptSeq),
			PlayerId = userIdOf(player),
			ProductId = productId,
			CurrencySpent = 100,
			CurrencyType = Enum.item("CurrencyType", "Robux"),
			PlaceIdWherePurchased = getmt(game).props.PlaceId or 0,
			ProductPurchaseChannel = Enum.item("ProductPurchaseChannel", "InExperience"),
		}
		local ctx = Svc.ctxOfGame(game)
		local h = Sched.invoke(ctx, cb, info)
		Sched.await(h, 30)
		if not h.done then
			return nil, "ProcessReceipt hat nach 30 s nicht geantwortet"
		end
		if not h.ok then
			return nil, h.err, h.traceback
		end
		return h.results[1], nil, nil, info
	end

	-- =================================================================================================
	--  PolicyService
	-- =================================================================================================
	local function policyFor(player)
		return {
			AreAdsAllowed = true,
			ArePaidRandomItemsRestricted = false,
			AllowedExternalLinkReferences = { "Discord", "Facebook", "Twitch", "YouTube", "X", "GitHub", "Guilded" },
			IsContentSharingAllowed = true,
			IsEligibleToPurchaseCommerceProduct = true,
			IsEligibleToPurchaseSubscription = true,
			IsPaidItemTradingAllowed = true,
			IsPhotoToAvatarAllowed = true,
			IsSubjectToChinaPolicies = false,
			IsEndlessContentLoadAllowed = true,
			IsEndlessContentAutoplayAllowed = true,
		}
	end
	Mk.policyOverride = nil
	Inst.registerService("PolicyService", {
		methods = {
			GetPolicyInfoForPlayerAsync = function(self, player)
				Inst.checkSelf(self, "GetPolicyInfoForPlayerAsync")
				castPlayer(player, 1, "GetPolicyInfoForPlayerAsync")
				local ctx = Svc.ctxOf(self)
				if ctx.isClient and getmt(ctx.game).ext.localPlayer ~= player then
					raise("GetPolicyInfoForPlayerAsync: on the client, player must be the LocalPlayer")
				end
				Svc.latency(0.1)
				local p = policyFor(player)
				if Mk.policyOverride then
					for k, v in Mk.policyOverride do
						p[k] = v
					end
				end
				return p
			end,
		},
	})

	-- =================================================================================================
	--  BadgeService / GroupService / SocialService / ExperienceNotification / AvatarEditor / Asset / Voice
	-- =================================================================================================
	Mk.badges = {}
	Inst.registerService("BadgeService", {
		methods = {
			AwardBadgeAsync = function(self, userId, badgeId)
				Inst.checkSelf(self, "AwardBadgeAsync")
				userId = castNumber(userId, 1, "AwardBadgeAsync")
				badgeId = castNumber(badgeId, 2, "AwardBadgeAsync")
				if Svc.ctxOf(self).isClient then
					raise("AwardBadgeAsync can only be called from the server")
				end
				Svc.latency(0.1)
				if badgeId <= 0 then
					raise("Unable to award badge: invalid badge id")
				end
				Mk.badges[userId] = Mk.badges[userId] or {}
				Mk.badges[userId][badgeId] = true
				return true
			end,
			UserHasBadgeAsync = function(self, userId, badgeId)
				Inst.checkSelf(self, "UserHasBadgeAsync")
				userId = castNumber(userId, 1, "UserHasBadgeAsync")
				badgeId = castNumber(badgeId, 2, "UserHasBadgeAsync")
				Svc.latency(0.1)
				return Mk.badges[userId] ~= nil and Mk.badges[userId][badgeId] == true
			end,
			CheckUserBadgesAsync = function(self, userId, badgeIds)
				Inst.checkSelf(self, "CheckUserBadgesAsync")
				userId = castNumber(userId, 1, "CheckUserBadgesAsync")
				if type(badgeIds) ~= "table" then
					Util.badArg(2, "CheckUserBadgesAsync", "table", badgeIds)
				end
				Svc.latency(0.1)
				local out = {}
				for _, id in badgeIds do
					if Mk.badges[userId] and Mk.badges[userId][id] then
						out[#out + 1] = id
					end
				end
				return out
			end,
			GetBadgeInfoAsync = function(self, badgeId)
				Inst.checkSelf(self, "GetBadgeInfoAsync")
				badgeId = castNumber(badgeId, 1, "GetBadgeInfoAsync")
				Svc.latency(0.1)
				return { Name = "Badge " .. badgeId, Description = "", IconImageId = 0, IsEnabled = true }
			end,
		},
	})

	Inst.registerService("GroupService", {
		methods = {
			GetGroupInfoAsync = function(self, groupId)
				Inst.checkSelf(self, "GetGroupInfoAsync")
				groupId = castNumber(groupId, 1, "GetGroupInfoAsync")
				Svc.latency(0.1)
				local g = Mk.groups and Mk.groups[groupId]
				if g == nil then
					raise("GroupService:GetGroupInfoAsync() failed because HTTP 400 (Group is invalid or does not exist.)")
				end
				return {
					Name = g.Name or ("Group " .. groupId),
					Id = groupId,
					Owner = { Name = g.OwnerName or "Owner", Id = g.OwnerId or 1 },
					EmblemUrl = "",
					Description = "",
					Roles = g.Roles or { { Name = "Member", Rank = 1 }, { Name = "Owner", Rank = 255 } },
				}
			end,
			GetGroupsAsync = function(self, userId)
				Inst.checkSelf(self, "GetGroupsAsync")
				userId = castNumber(userId, 1, "GetGroupsAsync")
				Svc.latency(0.1)
				local out = {}
				local u = Svc.Players and Svc.Players.users[userId]
				for id, info in (u and u.groups) or {} do
					out[#out + 1] = {
						Name = "Group " .. id,
						Id = id,
						EmblemUrl = "",
						EmblemId = 0,
						Rank = info.Rank or 1,
						Role = info.Role or "Member",
						IsPrimary = false,
						IsInClan = false,
					}
				end
				return out
			end,
			GetAlliesAsync = function(self, groupId)
				Inst.checkSelf(self, "GetAlliesAsync")
				castNumber(groupId, 1, "GetAlliesAsync")
				Svc.latency(0.1)
				return Svc.newPages("StandardPages", { {} })
			end,
			GetEnemiesAsync = function(self, groupId)
				Inst.checkSelf(self, "GetEnemiesAsync")
				castNumber(groupId, 1, "GetEnemiesAsync")
				Svc.latency(0.1)
				return Svc.newPages("StandardPages", { {} })
			end,
			PromptJoinAsync = function(self, groupId)
				Inst.checkSelf(self, "PromptJoinAsync")
				castNumber(groupId, 1, "PromptJoinAsync")
				if not Svc.ctxOf(self).isClient then
					raise("PromptJoinAsync can only be called from the client")
				end
				Svc.latency(0.5)
				return Enum.item("GroupMembershipStatus", "None")
			end,
		},
	})

	Inst.registerService("SocialService", {
		methods = {
			CanSendGameInviteAsync = function(self, player, recipientId)
				Inst.checkSelf(self, "CanSendGameInviteAsync")
				castPlayer(player, 1, "CanSendGameInviteAsync")
				Svc.latency(0.1)
				return false
			end,
			PromptGameInvite = function(self, player, options)
				Inst.checkSelf(self, "PromptGameInvite")
				castPlayer(player, 1, "PromptGameInvite")
				if options ~= nil and not (Inst.meta(options) and Inst.meta(options).cls.isA.ExperienceInviteOptions) then
					raise("Unable to cast value to Object")
				end
				Sched.addTimer(Sched.now + 0.5, function()
					Inst.fire(self, "GameInvitePromptClosed", player, {})
				end)
			end,
			CanSendCallInviteAsync = function(self, player)
				Inst.checkSelf(self, "CanSendCallInviteAsync")
				Svc.latency(0.1)
				return false
			end,
		},
	})

	Inst.registerService("ExperienceNotificationService", {
		methods = {
			CanPromptOptInAsync = function(self)
				Inst.checkSelf(self, "CanPromptOptInAsync")
				if not Svc.ctxOf(self).isClient then
					raise("CanPromptOptInAsync can only be called from the client")
				end
				Svc.latency(0.1)
				return false
			end,
			PromptOptIn = function(self)
				Inst.checkSelf(self, "PromptOptIn")
				Sched.addTimer(Sched.now + 0.5, function()
					Inst.fire(self, "OptInPromptClosed")
				end)
			end,
		},
	})

	Inst.registerService("AvatarEditorService", {
		methods = {
			PromptSetFavorite = function(self, itemId, itemType, shouldFavorite)
				Inst.checkSelf(self, "PromptSetFavorite")
				castNumber(itemId, 1, "PromptSetFavorite")
				castEnum(itemType, "AvatarItemType", 2, "PromptSetFavorite")
				if type(shouldFavorite) ~= "boolean" then
					Util.badArg(3, "PromptSetFavorite", "boolean", shouldFavorite)
				end
				Sched.addTimer(Sched.now + 0.5, function()
					Inst.fire(self, "PromptSetFavoriteCompleted", Enum.item("AvatarPromptResult", "Failed"))
				end)
			end,
		},
	})

	Inst.registerService("AssetService", {
		methods = {
			CreateMeshPartAsync = function(self, meshId, options)
				Inst.checkSelf(self, "CreateMeshPartAsync")
				local id = meshId
				if typeof(meshId) == "Content" then
					id = tostring(meshId)
				else
					id = castString(meshId, 1, "CreateMeshPartAsync")
				end
				Svc.latency(0.2)
				local mp = Inst.create("MeshPart", { Name = "MeshPart" })
				getmt(mp).props.MeshId = id
				return mp
			end,
		},
	})

	Inst.registerService("VoiceChatService", {
		methods = {
			IsVoiceEnabledForUserIdAsync = function(self, userId)
				Inst.checkSelf(self, "IsVoiceEnabledForUserIdAsync")
				castNumber(userId, 1, "IsVoiceEnabledForUserIdAsync")
				Svc.latency(0.1)
				return false
			end,
		},
	})

	-- =================================================================================================
	--  LocalizationService + Translator
	-- =================================================================================================
	local function localeOf(ctx)
		local game = ctx and ctx.game
		local lp = game and getmt(game).ext.localPlayer
		if lp then
			return getmt(lp).props.LocaleId or "en-us"
		end
		return "en-us"
	end
	local function newTranslator(locale)
		local t = Inst.create("Translator", { Name = "Translator" })
		getmt(t).props.LocaleId = locale
		return t
	end
	Inst.define("Translator", {
		methods = {
			Translate = function(self, context, text)
				Inst.checkSelf(self, "Translate")
				return castString(text, 2, "Translate")
			end,
			FormatByKey = function(self, key, args)
				Inst.checkSelf(self, "FormatByKey")
				key = castString(key, 1, "FormatByKey")
				raise(fmt("Translator:FormatByKey(): key '%s' not found", key))
			end,
		},
	})
	Inst.registerService("LocalizationService", {
		props = {
			RobloxLocaleId = {
				get = function(u)
					return localeOf(Svc.ctxOf(u))
				end,
			},
			SystemLocaleId = {
				get = function(u)
					return localeOf(Svc.ctxOf(u))
				end,
			},
		},
		methods = {
			GetTranslatorForPlayerAsync = function(self, player)
				Inst.checkSelf(self, "GetTranslatorForPlayerAsync")
				castPlayer(player, 1, "GetTranslatorForPlayerAsync")
				Svc.latency(0.1)
				return newTranslator(getmt(player).props.LocaleId or "en-us")
			end,
			GetTranslatorForPlayer = function(self, player)
				Inst.checkSelf(self, "GetTranslatorForPlayer")
				castPlayer(player, 1, "GetTranslatorForPlayer")
				return newTranslator(getmt(player).props.LocaleId or "en-us")
			end,
			GetTranslatorForLocaleAsync = function(self, locale)
				Inst.checkSelf(self, "GetTranslatorForLocaleAsync")
				locale = castString(locale, 1, "GetTranslatorForLocaleAsync")
				Svc.latency(0.1)
				return newTranslator(locale)
			end,
			GetCountryRegionForPlayerAsync = function(self, player)
				Inst.checkSelf(self, "GetCountryRegionForPlayerAsync")
				castPlayer(player, 1, "GetCountryRegionForPlayerAsync")
				Svc.latency(0.1)
				local loc = getmt(player).props.LocaleId or "en-us"
				local region = string.match(loc, "%-(%a%a)$")
				return region and string.upper(region) or "US"
			end,
		},
	})

	-- =================================================================================================
	--  AnalyticsService
	-- =================================================================================================
	Mk.analytics = {}
	local function logEvent(kind, ...)
		if #Mk.analytics < 2000 then
			Mk.analytics[#Mk.analytics + 1] = { kind = kind, t = Sched.now, args = table.pack(...) }
		end
	end
	local AS = {}
	function AS.LogEconomyEvent(self, player, flowType, currency, amount, ending, txType, sku, fields)
		Inst.checkSelf(self, "LogEconomyEvent")
		castPlayer(player, 1, "LogEconomyEvent")
		castEnum(flowType, "AnalyticsEconomyFlowType", 2, "LogEconomyEvent")
		castString(currency, 3, "LogEconomyEvent")
		castNumber(amount, 4, "LogEconomyEvent")
		castNumber(ending, 5, "LogEconomyEvent")
		castString(txType, 6, "LogEconomyEvent")
		if sku ~= nil then
			castString(sku, 7, "LogEconomyEvent")
		end
		castDict(fields, 8, "LogEconomyEvent")
		logEvent("Economy", flowType, currency, amount, ending, txType, sku)
	end
	function AS.LogProgressionEvent(self, player, path, status, level, levelName, fields)
		Inst.checkSelf(self, "LogProgressionEvent")
		castPlayer(player, 1, "LogProgressionEvent")
		castString(path, 2, "LogProgressionEvent")
		castEnum(status, "AnalyticsProgressionType", 3, "LogProgressionEvent")
		castNumber(level, 4, "LogProgressionEvent")
		if levelName ~= nil then
			castString(levelName, 5, "LogProgressionEvent")
		end
		castDict(fields, 6, "LogProgressionEvent")
		logEvent("Progression", path, status, level)
	end
	for _, nm in { "LogProgressionStartEvent", "LogProgressionCompleteEvent", "LogProgressionFailEvent" } do
		if R.api.classes.AnalyticsService.m[nm] then
			AS[nm] = function(self, player, path, level, levelName, fields)
				Inst.checkSelf(self, nm)
				castPlayer(player, 1, nm)
				castString(path, 2, nm)
				castNumber(level, 3, nm)
				logEvent(nm, path, level)
			end
		end
	end
	function AS.LogOnboardingFunnelStepEvent(self, player, step, stepName, fields)
		Inst.checkSelf(self, "LogOnboardingFunnelStepEvent")
		castPlayer(player, 1, "LogOnboardingFunnelStepEvent")
		castNumber(step, 2, "LogOnboardingFunnelStepEvent")
		if stepName ~= nil then
			castString(stepName, 3, "LogOnboardingFunnelStepEvent")
		end
		castDict(fields, 4, "LogOnboardingFunnelStepEvent")
		logEvent("Onboarding", step, stepName)
	end
	function AS.LogFunnelStepEvent(self, player, funnelName, sessionId, step, stepName, fields)
		Inst.checkSelf(self, "LogFunnelStepEvent")
		castPlayer(player, 1, "LogFunnelStepEvent")
		castString(funnelName, 2, "LogFunnelStepEvent")
		if sessionId ~= nil then
			castString(sessionId, 3, "LogFunnelStepEvent")
		end
		if step ~= nil then
			castNumber(step, 4, "LogFunnelStepEvent")
		end
		castDict(fields, 6, "LogFunnelStepEvent")
		logEvent("Funnel", funnelName, step)
	end
	function AS.LogCustomEvent(self, player, eventName, value, fields)
		Inst.checkSelf(self, "LogCustomEvent")
		castPlayer(player, 1, "LogCustomEvent")
		castString(eventName, 2, "LogCustomEvent")
		if value ~= nil then
			castNumber(value, 3, "LogCustomEvent")
		end
		castDict(fields, 4, "LogCustomEvent")
		logEvent("Custom", eventName, value)
	end
	Inst.registerService("AnalyticsService", { methods = AS })

	-- =================================================================================================
	--  HttpService
	-- =================================================================================================
	local HS = {}
	function HS.JSONEncode(self, value)
		Inst.checkSelf(self, "JSONEncode")
		return DT.json.encode(value)
	end
	function HS.JSONDecode(self, text)
		Inst.checkSelf(self, "JSONDecode")
		text = castString(text, 1, "JSONDecode")
		return DT.json.decode(text)
	end
	function HS.GenerateGUID(self, curly)
		Inst.checkSelf(self, "GenerateGUID")
		local rng = R.rng
		local function hex(n)
			local s = {}
			for i = 1, n do
				s[i] = string.format("%X", rng:NextInteger(0, 15))
			end
			return table.concat(s)
		end
		local g = hex(8) .. "-" .. hex(4) .. "-4" .. hex(3) .. "-" .. string.format("%X", rng:NextInteger(8, 11)) .. hex(3) .. "-" .. hex(12)
		if curly == nil or curly == true then
			return "{" .. g .. "}"
		end
		return g
	end
	function HS.UrlEncode(self, text)
		Inst.checkSelf(self, "UrlEncode")
		text = castString(text, 1, "UrlEncode")
		return (string.gsub(text, "[^%w%-%._~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end
	local function httpDenied(self)
		local ctx = Svc.ctxOf(self)
		if ctx.isClient then
			raise("Http requests can only be executed by game server")
		end
		raise("Http requests are not enabled. Enable via game settings")
	end
	for _, m in { "RequestAsync", "GetAsync", "PostAsync" } do
		HS[m] = function(self, ...)
			Inst.checkSelf(self, m)
			httpDenied(self)
		end
	end
	function HS.GetSecret(self, key)
		Inst.checkSelf(self, "GetSecret")
		castString(key, 1, "GetSecret")
		raise("Can't find secret with given key")
	end
	Inst.registerService("HttpService", { methods = HS })
end
