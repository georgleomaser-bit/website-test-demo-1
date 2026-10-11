--!strict
-- =====================================================================
--  CLUTCH CLASH – Kampf-Einstellungen (Shared/Config/Combat) -> Config.Combat
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C15, C10, C11, B13.
--  Treffer-Registrierung, Rückspulen, Hitboxen, Toleranzen. Startwerte aus DESIGN.md.
--  ACHTUNG: wird an alle Clients repliziert -> keine Geheimnisse.
--
--  Abschnitte:
--    1) Rückspulen & Verlauf       2) Hitboxen        3) Schuss-Prüfung (C10)
--    4) Nahkampf, Pop, Assists     5) Projektile       6) Sonstiges (Anti-Camp, Zielfernrohr)
--    7) Ergänzungen von WP3 (nicht im Schema-Auszug, aber hier zentral einstellbar)
--  Validate(Config): { string } prüft alle Zahlen (SelfTest + Boot-warn).
-- =====================================================================

local Combat = {
	-- -----------------------------------------------------------------
	-- 1) RÜCKSPULEN & VERLAUF (HistoryService)
	-- -----------------------------------------------------------------
	InterpDelay = 0.10, -- so weit hinkt die Sicht des Schützen hinterher (Roblox-Interpolation)
	MaxRewind = 0.38, -- höchstens so weit wird zurückgespult
	RewindWindow = 0.075, -- zusätzlich T−0.075 und T+0.075 prüfen
	HistoryHz = 30, -- Proben pro Sekunde
	HistorySlots = 24, -- Ringpuffer-Größe (24 / 30 Hz = 0.8 s)

	-- -----------------------------------------------------------------
	-- 2) HITBOXEN (B13.2) – feste Größe für jeden Avatar
	-- -----------------------------------------------------------------
	HitTol = 0.35, -- Toleranz (Studs) auf Kopf-Kugel und Körper-Kasten
	HeadRadius = 0.8, -- × rules.HeadRadiusMult (BigHeads 1.6)
	BodyOffset = Vector3.new(0, -1, 0), -- Mitte des Körper-Kastens relativ zum HRP
	BodyHalf = Vector3.new(1.5, 2.0, 0.8), -- Halbmaße (Boden bis Schulter, Arme inklusive)
	HeadTieBreak = 0.5, -- Kopf gewinnt, wenn sein Eintritt höchstens so viel weiter ist

	-- -----------------------------------------------------------------
	-- 3) SCHUSS-PRÜFUNG (C10)
	-- -----------------------------------------------------------------
	OriginTol = 4, -- Ursprung darf so weit vom Server-Kopf weg sein ...
	OriginSpeedCap = 0.4, -- ... plus Tempo × min(Alter, 0.4)
	LosShorten = 0.75, -- Sichtlinien-Strahl endet so viel vor dem Treffpunkt
	AgeMin = -0.05, -- Paket-Alter (Server-Zeit − t) mindestens ...
	AgeMax = 1.0, -- ... und höchstens
	PingSlack = 0.35, -- Alter <= Ping + 0.35
	IntervalTolerance = 0.75, -- Abstand der Zeitstempel >= Interval × 0.75
	RecvTolerance = 0.5, -- Empfangsabstand am Server >= Interval × 0.5
	PerSecondFactor = 1.15, -- Schüsse pro Sekunde <= 1/Interval × 1.15 + 1
	ShotIdGap = 4, -- shotId darf höchstens um 4 springen (Paketverlust)
	AimNormTol = 0.01, -- |aim| muss in [0.99, 1.01] liegen
	MaxScale = 30, -- größter erlaubter Spread-Anspruch (Grad)

	-- -----------------------------------------------------------------
	-- 4) NAHKAMPF, POP, ASSISTS (B11.4, B13.1)
	-- -----------------------------------------------------------------
	MeleeRangeSlack = 1.5, -- Reichweite + 1.5
	MeleeConeSlack = 10, -- Kegel/2 + 10°
	KillCreditWindow = 8, -- letzter Schadensverursacher <= 8 s bekommt den Pop
	AssistDamage = 25, -- Assist: mindestens 25 Schaden ...
	AssistWindow = 8, -- ... in den letzten 8 s vor dem Pop

	-- -----------------------------------------------------------------
	-- 5) PROJEKTILE (C11)
	-- -----------------------------------------------------------------
	RocketJump = { Radius = 4, Up = 55 }, -- eigene Rakete <= 4 Studs von den Füßen -> 55 nach oben
	ImpulseGrace = 1.5, -- Anti-Cheat-Gnade nach Rückstoß/Raketensprung (s)
	ImpulseMaxSpeed = 95, -- erlaubtes Tempo während der Gnade
	ProjectileRadius = 0.5, -- Kugel-gegen-Strahl-Radius der Projektile
	MaxFastForward = 0.15, -- Projektile werden um min(Alter, 0.15) vorgespult

	-- -----------------------------------------------------------------
	-- 6) SONSTIGES
	-- -----------------------------------------------------------------
	RecapMax = 12, -- Todes-Rückblick: letzte 12 Treffer
	AntiCamp = { Duel = 30, Team = 40, Pulse = 10, Show = 1 }, -- B6.5 (MatchService)
	ScopeGlintAfter = 0.3, -- Zielfernrohr-Glanz für Gegner nach 0.3 s ADS
	ScopeHitKick = 2, -- Treffer während ADS -> 2° Kamera-Kick

	-- -----------------------------------------------------------------
	-- 7) ERGÄNZUNGEN VON WP3 (zentral statt fest im Code)
	-- -----------------------------------------------------------------
	MovingSpeed = 10, -- ab diesem Tempo (Studs/s) rechnet der Server SpreadMove in die Untergrenze ein.
	-- Bewusst großzügig (Gehen = 16): der Client darf SpreadMove schon früher addieren, nie später.
	AdsGrace = 0.1, -- Zielen gilt AdsTime − 0.1 s nach dem Anlegen als "fertig" (C10 Schritt 7)
	ThrowChargedSpeed = 90, -- Wurf voll aufgeladen (0.5 s halten); Tippen = Projectile.Speed (70)
	ThrowFullHold = 0.5, -- so lange halten = charge 1.0 (Client)
	KillYHz = 5, -- Prüftakt für Sturz unter KillY, fehlende Teile, Regeneration
	VaultSpacing = 3, -- Abstand der Roster-Plätze im Tresor
	Admin = { -- Admin-Waffen B11.7
		OrbitalRay = 1000, -- Markier-Strahl
		OrbitalDelay = 1.0, -- Warnkreis-Dauer
		OrbitalRadius = 10, -- Himmelsstrahl-Radius
		OrbitalDamage = 999,
		MinigunSpinUp = 0.4, -- Anlauf (Client)
		VortexTime = 4, -- Wirbel-Dauer
		VortexDamageRadius = 18,
		VortexPullRadius = 25,
		VortexDps = 25,
		VortexImplosion = 150,
		VortexPull = 28, -- Zug-Tempo (Studs/s)
		VortexHz = 4,
		LightningJumps = 4, -- weitere Ziele
		LightningJumpRange = 20,
		LightningDamage = 80,
	},
}

-- ---------------------------------------------------------------------
-- PRÜFEN (leere Liste = alles ok)
-- ---------------------------------------------------------------------
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Combat.Validate(_config: any): { string }
	local errors: { string } = {}
	local function num(path: string, value: any, min: number, max: number?)
		if not isNum(value) then
			table.insert(errors, "Config.Combat." .. path .. ": Zahl erwartet")
		elseif value < min or (max ~= nil and value > max) then
			table.insert(
				errors,
				("Config.Combat.%s: %s liegt außerhalb [%s, %s]"):format(
					path,
					tostring(value),
					tostring(min),
					tostring(max or "∞")
				)
			)
		end
	end
	local c: any = Combat
	num("InterpDelay", c.InterpDelay, 0, 0.5)
	num("MaxRewind", c.MaxRewind, 0, 1)
	num("RewindWindow", c.RewindWindow, 0, 0.3)
	num("HistoryHz", c.HistoryHz, 1, 60)
	num("HistorySlots", c.HistorySlots, 2, 120)
	num("HitTol", c.HitTol, 0, 2)
	num("HeadRadius", c.HeadRadius, 0.1, 5)
	num("HeadTieBreak", c.HeadTieBreak, 0, 5)
	num("OriginTol", c.OriginTol, 0, 50)
	num("OriginSpeedCap", c.OriginSpeedCap, 0, 2)
	num("LosShorten", c.LosShorten, 0, 5)
	num("AgeMin", c.AgeMin, -1, 0)
	num("AgeMax", c.AgeMax, 0, 5)
	num("PingSlack", c.PingSlack, 0, 5)
	num("IntervalTolerance", c.IntervalTolerance, 0, 1)
	num("RecvTolerance", c.RecvTolerance, 0, 1)
	num("PerSecondFactor", c.PerSecondFactor, 1, 5)
	num("ShotIdGap", c.ShotIdGap, 1, 64)
	num("AimNormTol", c.AimNormTol, 0, 0.5)
	num("MaxScale", c.MaxScale, 1, 89)
	num("MeleeRangeSlack", c.MeleeRangeSlack, 0, 10)
	num("MeleeConeSlack", c.MeleeConeSlack, 0, 90)
	num("KillCreditWindow", c.KillCreditWindow, 0, 60)
	num("AssistDamage", c.AssistDamage, 0, 1000)
	num("AssistWindow", c.AssistWindow, 0, 60)
	num("ImpulseGrace", c.ImpulseGrace, 0, 10)
	num("ImpulseMaxSpeed", c.ImpulseMaxSpeed, 0, 500)
	num("ProjectileRadius", c.ProjectileRadius, 0, 5)
	num("MaxFastForward", c.MaxFastForward, 0, 1)
	num("RecapMax", c.RecapMax, 1, 50)
	num("ScopeGlintAfter", c.ScopeGlintAfter, 0, 5)
	num("ScopeHitKick", c.ScopeHitKick, 0, 20)
	num("MovingSpeed", c.MovingSpeed, 0, 50)
	num("AdsGrace", c.AdsGrace, 0, 1)
	num("ThrowChargedSpeed", c.ThrowChargedSpeed, 1, 500)
	num("ThrowFullHold", c.ThrowFullHold, 0.05, 5)
	num("KillYHz", c.KillYHz, 1, 30)
	num("VaultSpacing", c.VaultSpacing, 1, 10)
	if c.MaxRewind < c.InterpDelay then
		table.insert(errors, "Config.Combat.MaxRewind: muss >= InterpDelay sein")
	end
	if isNum(c.HistorySlots) and isNum(c.HistoryHz) and c.HistorySlots / c.HistoryHz < c.MaxRewind + c.RewindWindow then
		table.insert(errors, "Config.Combat.HistorySlots: Verlauf zu kurz für MaxRewind + RewindWindow")
	end
	for _, name in ipairs({ "BodyOffset", "BodyHalf" }) do
		local v = c[name]
		if typeof(v) ~= "Vector3" or not (isNum(v.X) and isNum(v.Y) and isNum(v.Z)) then
			table.insert(errors, "Config.Combat." .. name .. ": Vector3 erwartet")
		end
	end
	if typeof(c.BodyHalf) == "Vector3" and (c.BodyHalf.X <= 0 or c.BodyHalf.Y <= 0 or c.BodyHalf.Z <= 0) then
		table.insert(errors, "Config.Combat.BodyHalf: alle Halbmaße müssen > 0 sein")
	end
	if type(c.RocketJump) ~= "table" then
		table.insert(errors, "Config.Combat.RocketJump: Tabelle erwartet")
	else
		num("RocketJump.Radius", c.RocketJump.Radius, 0, 50)
		num("RocketJump.Up", c.RocketJump.Up, 0, 300)
	end
	if type(c.AntiCamp) ~= "table" then
		table.insert(errors, "Config.Combat.AntiCamp: Tabelle erwartet")
	else
		for _, key in ipairs({ "Duel", "Team", "Pulse", "Show" }) do
			num("AntiCamp." .. key, c.AntiCamp[key], 0, 600)
		end
	end
	if type(c.Admin) ~= "table" then
		table.insert(errors, "Config.Combat.Admin: Tabelle erwartet")
	else
		for key, value in pairs(c.Admin) do
			num("Admin." .. tostring(key), value, 0, 100000)
		end
	end
	return errors
end

return Combat
