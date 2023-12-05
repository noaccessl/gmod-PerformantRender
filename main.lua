--[[---------------------------------------------------------------------------
	Predefines
---------------------------------------------------------------------------]]
local _R = debug.getregistry()
local VECTOR = _R.Vector
local ENTITY = _R.Entity

--
--	Meta: ConVar
--
local ConVarGetBool = _R.ConVar.GetBool

--
--	Meta: Vector
--
local VectorDistToSqr = VECTOR.DistToSqr

--
--	Meta: Entity
--
local IsValid = ENTITY.IsValid
local IsDormant = ENTITY.IsDormant

local GetTable = ENTITY.GetTable
local GetPos = ENTITY.GetPos
local GetModelRadius = ENTITY.GetModelRadius
local WorldSpaceAABB = ENTITY.WorldSpaceAABB

local SetNoDraw = ENTITY.SetNoDraw
local GetNoDraw = ENTITY.GetNoDraw

local RemoveEFlags = ENTITY.RemoveEFlags
local AddEFlags = ENTITY.AddEFlags

--
--	Globals
--
local GetFogDistances = render.GetFogDistances
local CalculatePixelVisibility = util.PixelVisible

local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

--
--	Utilities
--
local IsInFOV

do

	local MathAbs = math.abs
	local RAD2DEG = 180 / math.pi
	local MathAcos = math.acos

	local VectorCopy = VECTOR.Set
	local VectorSub = VECTOR.Sub
	local VectorNormalize = VECTOR.Normalize
	local VectorDot = VECTOR.Dot

	local diff = Vector()

	function IsInFOV( vecViewOrigin, vecViewDirection, vecPoint, flFOV )

		VectorCopy( diff, vecPoint )
		VectorSub( diff, vecViewOrigin )
		VectorNormalize( diff )

		return MathAbs( RAD2DEG * ( MathAcos( VectorDot( vecViewDirection, diff ) ) ) ) < flFOV

	end

end




--[[---------------------------------------------------------------------------
	PerformantRender
---------------------------------------------------------------------------]]
local PERFRENDER_STATE = CreateClientConVar( 'r_performant_enable', '1', true, false, 'Enables/Disables performant rendering of props, NPCs, SENTs, etc.', 0, 1 )
local PERFRENDER_DEBUG = CreateClientConVar( 'r_performant_debug', '0', false, false, 'Enables/Disables performant render debugging.', 0, 1 )

cvars.AddChangeCallback( 'r_performant_enable', function( _, _, new )

	if tobool( new ) then

		local tEnts = ents.GetAll()
		local RegisterPotentialRenderable = hook.GetTable().OnEntityCreated.PerformantRender

		for numIndex = 1, #tEnts do

			local pEntity = tEnts[numIndex]

			if IsValid( pEntity ) and not pEntity.m_PixVis then
				RegisterPotentialRenderable( pEntity )
			end

		end

		return

	end

	local g_Renderables = g_Renderables
	local numAmount = #g_Renderables

	if numAmount == 0 then
		return
	end

	for numIndex = 1, numAmount do

		local pEntity = g_Renderables[numIndex]

		if IsValid( pEntity ) then

			SetNoDraw( pEntity, false )
			RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			pEntity.m_bVisible = true

		end

	end

end, 'state' )

local function IsPerfRenderEnabled()
	return ConVarGetBool( PERFRENDER_STATE )
end

local function IsPerfRenderDebuggingEnabled()
	return ConVarGetBool( PERFRENDER_DEBUG )
end


g_Renderables = g_Renderables or {}


--[[---------------------------------------------------------------------------
	PerformantRender: Visibility Calculations
---------------------------------------------------------------------------]]
local AngleGetForward = _R.Angle.Forward
local IsEFlagSet = ENTITY.IsEFlagSet


local function CalculateRenderablesVisibility( vecViewOrigin, angViewOrigin, flFOV )

	local g_Renderables = g_Renderables
	local numAmount = #g_Renderables

	if numAmount == 0 then
		return
	end

	local vecViewDirection = AngleGetForward( angViewOrigin )

	for numIndex = 1, numAmount do

		local pEntity = g_Renderables[numIndex]

		if not IsValid( pEntity ) then

			table.remove( g_Renderables, numIndex )
			continue

		end

		if IsDormant( pEntity ) then
			continue
		end

		local vecOrigin = GetPos( pEntity )

		local vecMins, vecMaxs = WorldSpaceAABB( pEntity )
		local numRadiusSquared = VectorDistToSqr( vecMins, vecMaxs )

		local flDist = VectorDistToSqr( vecViewOrigin, vecOrigin )
		local bInDistance = flDist <= numRadiusSquared * 1.5625

		local bInFOV = IsInFOV( vecViewOrigin, vecViewDirection, vecOrigin, flFOV * 0.6 )

		if not bInDistance and not bInFOV then

			if not IsEFlagSet( pEntity, EFL_NO_THINK_FUNCTION ) then
				SetNoDraw( pEntity, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )
			end

			continue

		end

		local pEntity_t = GetTable( pEntity )

		local bVisible = false
		local bOutsidePVS = false

		local _, flFogEnd = GetFogDistances()
		local bInFog = false

		if flFogEnd > 0 then
			bInFog = flDist > flFogEnd * flFogEnd + numRadiusSquared * 1.5625
		end

		if bInDistance then
			bVisible = true
		elseif bInFog then
			bVisible = false
			bOutsidePVS = true
		elseif pEntity_t.m_PixVis then
			bVisible = CalculatePixelVisibility( vecOrigin, numRadiusSquared ^ 0.5, pEntity_t.m_PixVis ) > 0
		end

		local bNoDraw = GetNoDraw( pEntity )

		if bVisible then

			if bNoDraw then

				SetNoDraw( pEntity, false )
				RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

				pEntity_t.m_bVisible = true

			end

		else

			if not bNoDraw then

				SetNoDraw( pEntity, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )

				pEntity_t.m_bVisible = false

			end

		end

		pEntity_t.m_bOutsidePVS = bOutsidePVS

	end

end

hook.Add( 'RenderScene', 'CalculateRenderablesVisibility', function( vecViewOrigin, angViewOrigin, flFOV )

	if not IsPerfRenderEnabled() then
		return
	end

	CalculateRenderablesVisibility( vecViewOrigin, angViewOrigin, flFOV )

end )


--[[---------------------------------------------------------------------------
	PerformantRender: Setup
---------------------------------------------------------------------------]]
hook.Add( 'OnEntityCreated', 'PerformantRender', function( EntityNew )

	timer.Simple( 0, function()

		if not IsValid( EntityNew ) then
			return
		end

		if not GetModelRadius( EntityNew ) then
			return
		end

		local strModel = EntityNew:GetModel()

		if not isstring( strModel ) then
			return
		end

		if not strModel:StartsWith( 'models' ) or strModel == 'models/error.mdl' then
			return
		end

		if EntityNew:IsPlayer() or EntityNew:IsWeapon() or not EntityNew:IsSolid() then
			return
		end

		EntityNew.m_bVisible = true
		EntityNew.m_bOutsidePVS = true
		EntityNew.m_PixVis = util.GetPixelVisibleHandle()

		table.insert( g_Renderables, EntityNew )

	end )

end )


--[[---------------------------------------------------------------------------
	PerformantRender: Debugging
---------------------------------------------------------------------------]]
do

	local colorVisible = Color( 0, 180, 0 )
	local colorHidden = Color( 255, 50, 0 )

	local SetColorMaterial = render.SetColorMaterial

	local GetAngles = ENTITY.GetAngles

	local OBBMins = ENTITY.OBBMins
	local OBBMaxs = ENTITY.OBBMaxs

	local DrawWireframeBox = render.DrawWireframeBox

	hook.Add( 'PostDrawTranslucentRenderables', 'DebugRenderablesVisibility', function( _, _, bSky )

		if bSky then
			return
		end

		if not IsPerfRenderDebuggingEnabled() then
			return
		end

		local g_Renderables = g_Renderables
		local numAmount = #g_Renderables

		if numAmount == 0 then
			return
		end

		SetColorMaterial()

		for numIndex = 1, numAmount do

			local pEntity = g_Renderables[numIndex]

			if not IsValid( pEntity ) then
				continue
			end

			if IsDormant( pEntity ) or pEntity.m_bOutsidePVS == true then
				continue
			end

			local vecOrigin = GetPos( pEntity )
			local angOrigin = GetAngles( pEntity )

			local vecOBBMins = OBBMins( pEntity )
			local vecOBBMaxs = OBBMaxs( pEntity )

			if pEntity.m_bVisible == false then
				DrawWireframeBox( vecOrigin, angOrigin, vecOBBMins, vecOBBMaxs, colorHidden )
			else
				DrawWireframeBox( vecOrigin, angOrigin, vecOBBMins, vecOBBMaxs, colorVisible )
			end

		end

	end )

end