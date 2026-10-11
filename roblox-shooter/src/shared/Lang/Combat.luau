-- =====================================================================
--  CLUTCH CLASH – Texte "combat." (Shared/Lang/Combat)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Nur Schlüssel mit Präfix "combat.".
--  Auch für das Kampf-HUD von WP4/WP10 (Munition, Nachladen, Treffer, Rückblick).
--  Platzhalter wie string.format: %s = Text, %d = ganze Zahl.
--  Pflicht-Schlüssel (C16): combat.popped, combat.hpLeft, combat.dealt.
--  Reject-Codes (C10) für Debug-Overlay/Reject-Log: combat.reject.<CODE>.
-- =====================================================================

return {
	de = {
		-- Pflicht (C16)
		["combat.popped"] = "%s GEPOPPT",
		["combat.hpLeft"] = "REST-LEBEN: %d",
		["combat.dealt"] = "Du hast %d Schaden in %d Treffern gemacht (%d Kopf)",

		-- Treffer & Pops (B14.1)
		["combat.headshot"] = "HEADSHOT!",
		["combat.poppedBy"] = "GEPOPPT VON %s",
		["combat.assist"] = "ASSIST",
		["combat.assistOn"] = "Assist an %s",
		["combat.selfPop"] = "Selbst gepoppt!",
		["combat.void"] = "Ins Nichts gefallen",
		["combat.bonk"] = "BONK!",
		["combat.blocked"] = "GEBLOCKT",
		["combat.rocketJump"] = "Raketensprung!",

		-- Munition & Aktionen (Kampf-HUD)
		["combat.reload"] = "R – Nachladen",
		["combat.reloading"] = "Lädt nach…",
		["combat.noAmmo"] = "Leer!",
		["combat.lowAmmo"] = "Wenig Munition",
		["combat.charges"] = "%d Ladung(en)",
		["combat.cooldown"] = "Bereit in %d s",
		["combat.ready"] = "Bereit",
		["combat.healing"] = "Trinkt…",
		["combat.healed"] = "+%d LEBEN",
		["combat.blockCooldown"] = "Block bereit in %d s",
		["combat.spawnShield"] = "Spawn-Schutz",
		["combat.recap"] = "Todes-Rückblick",
		["combat.recapHit"] = "%s · %d Schaden%s · %d m",
		["combat.recapHead"] = " · KOPF",
		["combat.killer"] = "Gepoppt von",
		["combat.distance"] = "%d Studs",

		-- Waffen-Zugang (WeaponService)
		["combat.locked"] = "Diese Waffe musst du erst freischalten (Shop).",
		["combat.disabled"] = "Diese Waffe ist gerade deaktiviert.",
		["combat.slotBlocked"] = "Dieser Slot ist in diesem Modus gesperrt.",
		["combat.adminOnly"] = "Nur für den Besitzer.",
		["combat.adminWeapon"] = "Admin-Waffe ausgerüstet: %s",
		["combat.notArmed"] = "Du bist gerade in keinem Kampf.",

		-- Reject-Codes (C10) – nur Debug/Admin
		["combat.reject.TYPE"] = "Paket kaputt (Typ/Zahl/Ziel-Anzahl)",
		["combat.reject.RATE"] = "Zu schnell geschossen",
		["combat.reject.STATE"] = "Falscher Zustand (Schuss-Id, Munition, Nachladen, Phase)",
		["combat.reject.TIME"] = "Zeitstempel ungültig",
		["combat.reject.ORIGIN"] = "Ursprung zu weit weg oder hinter einer Wand",
		["combat.reject.HITBOX"] = "Hitbox verfehlt",
		["combat.reject.LOS"] = "Keine Sichtlinie (Wand)",
		["combat.reject.RANGE"] = "Außer Reichweite",
		["combat.reject.TARGET"] = "Ungültiges Ziel",
	},
	en = {
		-- Required (C16)
		["combat.popped"] = "POPPED %s",
		["combat.hpLeft"] = "HP LEFT: %d",
		["combat.dealt"] = "You dealt %d damage in %d hits (%d head)",

		-- Hits & pops (B14.1)
		["combat.headshot"] = "HEADSHOT!",
		["combat.poppedBy"] = "POPPED BY %s",
		["combat.assist"] = "ASSIST",
		["combat.assistOn"] = "Assist on %s",
		["combat.selfPop"] = "Popped yourself!",
		["combat.void"] = "Fell into the void",
		["combat.bonk"] = "BONK!",
		["combat.blocked"] = "BLOCKED",
		["combat.rocketJump"] = "Rocket jump!",

		-- Ammo & actions (combat HUD)
		["combat.reload"] = "R – Reload",
		["combat.reloading"] = "Reloading…",
		["combat.noAmmo"] = "Empty!",
		["combat.lowAmmo"] = "Low ammo",
		["combat.charges"] = "%d charge(s)",
		["combat.cooldown"] = "Ready in %d s",
		["combat.ready"] = "Ready",
		["combat.healing"] = "Drinking…",
		["combat.healed"] = "+%d HP",
		["combat.blockCooldown"] = "Block ready in %d s",
		["combat.spawnShield"] = "Spawn shield",
		["combat.recap"] = "Death recap",
		["combat.recapHit"] = "%s · %d damage%s · %d m",
		["combat.recapHead"] = " · HEAD",
		["combat.killer"] = "Popped by",
		["combat.distance"] = "%d studs",

		-- Weapon access (WeaponService)
		["combat.locked"] = "Unlock this weapon first (shop).",
		["combat.disabled"] = "This weapon is disabled right now.",
		["combat.slotBlocked"] = "This slot is locked in this mode.",
		["combat.adminOnly"] = "Owner only.",
		["combat.adminWeapon"] = "Admin weapon equipped: %s",
		["combat.notArmed"] = "You are not in a fight right now.",

		-- Reject codes (C10) – debug/admin only
		["combat.reject.TYPE"] = "Broken packet (type/number/target count)",
		["combat.reject.RATE"] = "Fired too fast",
		["combat.reject.STATE"] = "Wrong state (shot id, ammo, reload, phase)",
		["combat.reject.TIME"] = "Invalid timestamp",
		["combat.reject.ORIGIN"] = "Origin too far away or behind a wall",
		["combat.reject.HITBOX"] = "Hitbox missed",
		["combat.reject.LOS"] = "No line of sight (wall)",
		["combat.reject.RANGE"] = "Out of range",
		["combat.reject.TARGET"] = "Invalid target",
	},
}
