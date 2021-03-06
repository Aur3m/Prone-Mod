------------------------------------------------------------------
-- Define a bunch of really important meta functions we'll be using
-------------------------------------------------------------------
local PLAYER = FindMetaTable("Player")

function PLAYER:GetProneAnimationState()
	return self:GetNW2Int("prone.AnimationState", PRONE_NOTINPRONE)
end
function PLAYER:SetProneAnimationState(state)
	return self:SetNW2Int("prone.AnimationState", state)
end

function PLAYER:GetProneAnimationLength()
	return self:GetNW2Float("prone.AnimationLength", 0)
end
function PLAYER:SetProneAnimationLength(length)
	return self:SetNW2Float("prone.AnimationLength", length)
end

function PLAYER:IsProne()
	return self:GetProneAnimationState() <= PRONE_EXITTINGPRONE
end

function PLAYER:ProneIsGettingUp()
	return self:GetProneAnimationState() == PRONE_GETTINGUP
end

function PLAYER:ProneIsGettingDown()
	return self:GetProneAnimationState() == PRONE_GETTINGDOWN
end

-- Micro-Optimizatios!
local IsValid, CurTime, type, math_min = IsValid, CurTime, type, math.min

------------------------------------------------------------------
-- Handles pose parameters and the playback rate of the animations
------------------------------------------------------------------
local GetUpdateAnimationRate = {
	[PRONE_GETTINGDOWN] = 1,
	[PRONE_GETTINGUP] = 1
}
hook.Add("UpdateAnimation", "Prone.Animations", function(ply, velocity, maxSeqGroundSpeed)
	if ply:IsProne() then
		local length = velocity:Length()

		local rate = GetUpdateAnimationRate[ply:GetProneAnimationState()]
		if not rate then
			if not ply:IsOnGround() and length >= 750 then
				rate = 0.1
			else
				if length > 0.2 then
					rate = math_min(length / maxSeqGroundSpeed, 2)
				else
					rate = 1
				end
			end
		end

		if CLIENT then
			local EyeAngP = ply:EyeAngles().p
			if EyeAngP < 89 then
				ply:SetPoseParameter("body_pitch", math.Clamp(-EyeAngP, -10, 50))
				ply:SetPoseParameter("body_yaw", 0)
				ply:InvalidateBoneCache()
			end
		end

		ply:SetPlaybackRate(rate)
	end
end)

----------------------------------------
-- The animation powerhouse of the addon
----------------------------------------
local function GetSequenceForWeapon(holdtype, ismoving)
	return ismoving and prone.animations.WeaponAnims.moving[holdtype] or prone.animations.WeaponAnims.idle[holdtype]
end
local GetMainActivityAnimation = {
	[PRONE_GETTINGDOWN] = function(ply)
		if ply:GetProneAnimationLength() <= CurTime() then
			ply:SetViewOffset(prone.config.View)
			ply:SetViewOffsetDucked(prone.config.View)
			ply:SetProneAnimationState(PRONE_INPRONE)
		end
		
		return prone.animations.gettingdown
	end,

	[PRONE_GETTINGUP] = function(ply)
		if ply:GetProneAnimationLength() <= CurTime() then
			ply:SetViewOffset(ply.prone.oldviewoffset)
			ply:SetViewOffsetDucked(ply.prone.oldviewoffset_ducked)
			ply:SetProneAnimationState(PRONE_EXITTINGPRONE)
		end

		return prone.animations.gettingup
	end,

	[PRONE_INPRONE] = function(ply, velocity)
		local weapon = ply:GetActiveWeapon()
		local WeaponHoldType

		if IsValid(weapon) then
			WeaponHoldType = weapon:GetHoldType()
			if WeaponHoldType == "" then
				WeaponHoldType = weapon.HoldType
			end
		end

		return GetSequenceForWeapon(WeaponHoldType or "normal", velocity:LengthSqr() >= 225)
	end,

	[PRONE_EXITTINGPRONE] = function(ply)
		if SERVER then
			prone.Exit(ply)

			if not prone.CanExit(ply) then
				prone.Enter(ply)
			end
		end

		return prone.animations.passive
	end,

	-- Just in case this gets called for some reason.
	[PRONE_NOTINPRONE] = function()
		return prone.animations.passive
	end
}
hook.Add("CalcMainActivity", "Prone.Animations", function(ply, velocity)
	if IsValid(ply) and ply:IsPlayer() and ply:IsProne() then
		local seq = GetMainActivityAnimation[ply:GetProneAnimationState()](ply, velocity)

		-- NEVER let this hook's second return parameter be a number less than 0.
		-- That crashes Linux servers for some reason.
		local seqid = ply:LookupSequence(seq or "")
		if type(seqid) == "number" and seqid < 0 then
			return
		end

		return -1, seqid or nil
	end
end)

-- Restrict their movement.
hook.Add("SetupMove", "Prone.RestrictMovement", function(ply, cmd)
	if ply:IsProne() then
		if cmd:KeyDown(IN_JUMP) then
			cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_JUMP)))	-- Disables jumping, thanks meep
		end

		-- If they are getting up or down then set their speed to TransitionSpeed
		if ply:GetProneAnimationLength() >= CurTime() then
			cmd:SetMaxClientSpeed(prone.config.TransitionSpeed)
			cmd:SetMaxSpeed(prone.config.TransitionSpeed)

			if prone.config.TransitionSpeed <= 0 and ply:IsOnGround() then
				cmd:SetForwardSpeed(0)
				cmd:SetSideSpeed(0)
				cmd:SetVelocity(Vector(0, 0, 0))
			end
			return
		else	-- If they are in prone set their speed to MoveSpeed
			cmd:SetMaxClientSpeed(prone.config.MoveSpeed)
			cmd:SetMaxSpeed(prone.config.MoveSpeed)
		end

		local attack1 = cmd:KeyDown(IN_ATTACK)
		if attack1 or cmd:KeyDown(IN_ATTACK2) and prone.config.MoveShoot_Restrict then
			local weapon = ply:GetActiveWeapon()
			if not IsValid(weapon) then
				return
			end

			local weaponclass = weapon:GetClass()
			if not prone.config.MoveShoot_Whitelist[weaponclass] then
				local ShouldStopMovement = true
				if attack1 then
					ShouldStopMovement = weapon:Clip1() > 0
				else
					ShouldStopMovement = weapon:Clip2() > 0
				end

				if (ShouldStopMovement or weaponclass == "weapon_crowbar") and ply:IsOnGround() then
					cmd:SetForwardSpeed(0)
					cmd:SetSideSpeed(0)
					cmd:SetVelocity(Vector(0, 0, 0))
				end
			end
		end
	end
end)

-- TTT Movement support
hook.Add("TTTPlayerSpeed", "Prone.RestrictMovement", function(ply)
	if ply:IsProne() then
		return prone.config.MoveSpeed / 220	-- 220 is the default run speed in TTT
	end
end)