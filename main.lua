--[[---------------------------------------------------------------------------
	Prepare
---------------------------------------------------------------------------]]
local VECTOR = FindMetaTable( 'Vector' )
local ENTITY = FindMetaTable( 'Entity' )

--
-- Vector
--
local VectorDistToSqr = VECTOR.DistToSqr

--
-- Entity
--
local IsValid			= ENTITY.IsValid
local IsDormant			= ENTITY.IsDormant

local IsEFlagSet		= ENTITY.IsEFlagSet

local GetPos			= ENTITY.GetPos
local GetRenderBounds	= ENTITY.GetRenderBounds

local SetNoDraw			= ENTITY.SetNoDraw
local GetNoDraw			= ENTITY.GetNoDraw

local RemoveEFlags		= ENTITY.RemoveEFlags
local AddEFlags			= ENTITY.AddEFlags

--
-- Angle
--
local AngleGetForward = FindMetaTable( 'Angle' ).Forward

--
-- Globals
--
local MathCos = math.cos
local DEG2RAD = math.pi / 180

local GetFogDistances = render.GetFogDistances
local CalculatePixelVisibility = util.PixelVisible

local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

--
--	Utilities
--
local IsInFOV

do

	local VectorCopy		= VECTOR.Set
	local VectorSubtract	= VECTOR.Sub
	local VectorNormalize	= VECTOR.Normalize
	local VectorDot			= VECTOR.Dot

	local diff = Vector()

	function IsInFOV( vecViewOrigin, vecViewDirection, vecPoint, flFOVCosine )

		VectorCopy( diff, vecPoint )
		VectorSubtract( diff, vecViewOrigin )
		VectorNormalize( diff )

		return VectorDot( vecViewDirection, diff ) > flFOVCosine

	end

end

local function MacroAddCVarChangeCallback( name, callback )

	cvars.AddChangeCallback( name, function( _, _, new )
		callback( new )
	end, name )

end

local RegisterPotentialRenderable





--[[---------------------------------------------------------------------------
	PerformantRender
---------------------------------------------------------------------------]]
local PERFRENDER_STATE = CreateClientConVar( 'r_performant_enable', '1', true, false, 'Enables/Disables performant rendering of props, NPCs, SENTs, etc.', 0, 1 ):GetBool()
local PERFRENDER_CUTBEYONDFOG = CreateClientConVar( 'r_performant_cutbeyondfog', '1', true, false, 'Should we disable rendering entities that are beyond fog?', 0, 1 ):GetBool()
local PERFRENDER_DEBUG = CreateClientConVar( 'r_performant_debug', '0', false, false, 'Enables/Disables performant render debugging.', 0, 1 ):GetBool()

MacroAddCVarChangeCallback( 'r_performant_enable', function( new )

	PERFRENDER_STATE = tobool( new )

	if PERFRENDER_STATE then

		local iterate, overtable, startingfrom

		if ents.Iterator then
			iterate, overtable, startingfrom = ents.Iterator()
		else
			iterate, overtable, startingfrom = ipairs( ents.GetAll() )
		end

		for numIndex, pEntity in iterate, overtable, startingfrom do

			if IsValid( pEntity ) and not pEntity.m_bRenderable then
				RegisterPotentialRenderable( pEntity )
			end

		end

	else

		for numIndex, pEntity in ipairs( g_Renderables ) do

			if IsValid( pEntity ) then

				SetNoDraw( pEntity, false )
				RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

		end

	end

end )

MacroAddCVarChangeCallback( 'r_performant_cutbeyondfog', function( new )
	PERFRENDER_CUTBEYONDFOG = tobool( new )
end )

MacroAddCVarChangeCallback( 'r_performant_debug', function( new )
	PERFRENDER_DEBUG = tobool( new )
end )

g_Renderables = g_Renderables or {}
g_Renderables_Lookup = g_Renderables_Lookup or {}

--[[---------------------------------------------------------------------------
	PerformantRender: Visibility Calculations
---------------------------------------------------------------------------]]
local function CalculateRenderablesVisibility( vecViewOrigin, angViewOrigin, flFOV )

	local g_Renderables = g_Renderables
	local numAmount = #g_Renderables

	if numAmount == 0 then
		return
	end

	local g_Renderables_Lookup = g_Renderables_Lookup

	local vecViewDirection = AngleGetForward( angViewOrigin )
	local flFOVCosine = MathCos( DEG2RAD * ( flFOV * 0.75 ) )

	local PERFRENDER_CUTBEYONDFOG = PERFRENDER_CUTBEYONDFOG

	for numIndex = 1, numAmount do

		local pEntity = g_Renderables[ numIndex ]

		if not IsValid( pEntity ) then

			table.remove( g_Renderables, numIndex )
			g_Renderables_Lookup[ pEntity ] = nil

			break

		end

		if IsDormant( pEntity ) then
			continue
		end

		local vecOrigin = GetPos( pEntity )
		local pEntity_t = g_Renderables_Lookup[ pEntity ]

		local flDiagonalSqr = pEntity_t.m_flDiagonalSqr
		local flDist = VectorDistToSqr( vecViewOrigin, vecOrigin )

		local bInDistance = flDist <= flDiagonalSqr
		local bInFOV = IsInFOV( vecViewOrigin, vecViewDirection, vecOrigin, flFOVCosine )

		if not bInDistance and not bInFOV then

			if not IsEFlagSet( pEntity, EFL_NO_THINK_FUNCTION ) then

				SetNoDraw( pEntity, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

			continue

		end

		local bVisible = false
		local bOutsidePVS = false
		local bInFog = false

		if PERFRENDER_CUTBEYONDFOG then

			local _, flFogEnd = GetFogDistances()

			if flFogEnd > 0 then
				bInFog = flDist > flFogEnd * flFogEnd + flDiagonalSqr
			end

		end

		if bInDistance then
			bVisible = true
		elseif bInFog then
			bVisible = false
			bOutsidePVS = true
		elseif pEntity_t.m_PixVis then
			bVisible = CalculatePixelVisibility( vecOrigin, pEntity_t.m_flDiagonal, pEntity_t.m_PixVis ) > 0
		end

		local bNoDraw = GetNoDraw( pEntity )

		if bVisible then

			if bNoDraw then

				SetNoDraw( pEntity, false )
				RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

			pEntity_t.m_bVisible = true

		else

			if not bNoDraw then

				SetNoDraw( pEntity, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

			pEntity_t.m_bVisible = false

		end

		pEntity_t.m_bOutsidePVS = bOutsidePVS

	end

end

local VECTOR_VIEW_ORIGIN
local ANGLE_VIEW_ORIGIN
local FOV_VIEW
local MySelf = NULL

hook.Add( 'RenderScene', 'CalculateRenderablesVisibility', function( vecViewOrigin, angViewOrigin, flFOV )

	if not IsValid( MySelf ) then
		MySelf = LocalPlayer()
	end

	VECTOR_VIEW_ORIGIN = vecViewOrigin
	ANGLE_VIEW_ORIGIN = angViewOrigin
	FOV_VIEW = flFOV

end )

hook.Add( 'PreRender', 'CalculateRenderablesVisibility', function()

	if not PERFRENDER_STATE then
		return
	end

	if MySelf.tardis then
		return
	end

	if not VECTOR_VIEW_ORIGIN then
		return
	end

	CalculateRenderablesVisibility( VECTOR_VIEW_ORIGIN, ANGLE_VIEW_ORIGIN, FOV_VIEW )

end )

--[[---------------------------------------------------------------------------
	Compatibility with RT Cameras
---------------------------------------------------------------------------]]
render.RenderView_Internal = render.RenderView_Internal or render.RenderView

function render.RenderView( tView )

	local g_Renderables = g_Renderables
	local numAmount = #g_Renderables

	if numAmount == 0 then
		return render.RenderView_Internal( tView )
	end

	for numIndex = 1, numAmount do

		local pEntity = g_Renderables[ numIndex ]

		if IsValid( pEntity ) and not IsDormant( pEntity ) and GetNoDraw( pEntity ) then
			SetNoDraw( pEntity, false )
		end

	end

	render.RenderView_Internal( tView )

end

--[[---------------------------------------------------------------------------
	PerformantRender: Setup
---------------------------------------------------------------------------]]
local function CalcDiagonal( pEntity )

	local vecMins, vecMaxs = GetRenderBounds( pEntity )
	local flDiagonalSqr = VectorDistToSqr( vecMins, vecMaxs )

	local pEntity_t = g_Renderables_Lookup[ pEntity ]

	pEntity_t.m_flDiagonalSqr = flDiagonalSqr * 1.5625
	pEntity_t.m_flDiagonal = flDiagonalSqr ^ 0.5

end

ENTITY.SetRenderBounds_Internal	  = ENTITY.SetRenderBounds_Internal or ENTITY.SetRenderBounds
ENTITY.SetRenderBoundsWS_Internal = ENTITY.SetRenderBoundsWS_Internal or ENTITY.SetRenderBoundsWS

function ENTITY:SetRenderBounds( vecMins, vecMaxs, vecAdd )

	self:SetRenderBounds_Internal( vecMins, vecMaxs, vecAdd )

	if self.m_bRenderable then
		CalcDiagonal( self )
	end

end

function ENTITY:SetRenderBoundsWS( vecMins, vecMaxs, vecAdd )

	self:SetRenderBoundsWS_Internal( vecMins, vecMaxs, vecAdd )

	if self.m_bRenderable then
		CalcDiagonal( self )
	end

end

function RegisterPotentialRenderable( EntityNew )

	timer.Simple( 0, function()

		if not IsValid( EntityNew ) then
			return
		end

		if GetNoDraw( EntityNew ) then
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

		local strClass = EntityNew:GetClass()

		if strClass:sub( 6, 9 ) == 'door' then
			return
		end

		EntityNew.m_bRenderable = true

		g_Renderables_Lookup[ EntityNew ] = {

			m_bVisible = true;
			m_bOutsidePVS = false;
			m_PixVis = util.GetPixelVisibleHandle()

		}

		CalcDiagonal( EntityNew )

		table.insert( g_Renderables, EntityNew )

	end )

end
hook.Add( 'OnEntityCreated', 'PerformantRender', RegisterPotentialRenderable )

--[[---------------------------------------------------------------------------
	PerformantRender: Debugging
---------------------------------------------------------------------------]]
do

	local COLOR_VISIBLE = Color( 0, 180, 0 )
	local COLOR_HIDDEN  = Color( 255, 50, 0 )

	local SetColorMaterial = render.SetColorMaterial
	local DrawWireframeBox = render.DrawWireframeBox

	local GetAngles = ENTITY.GetAngles

	local sv_cheats = GetConVar( 'sv_cheats' ):GetBool()

	MacroAddCVarChangeCallback( 'sv_cheats', function( new )
		sv_cheats = tobool( new )
	end )

	hook.Add( 'PostDrawTranslucentRenderables', 'DebugRenderablesVisibility', function( _, _, bSky )

		if bSky then
			return
		end

		if not ( PERFRENDER_STATE and PERFRENDER_DEBUG and sv_cheats ) then
			return
		end

		local g_Renderables = g_Renderables
		local numAmount = #g_Renderables

		if numAmount == 0 then
			return
		end

		local g_Renderables_Lookup = g_Renderables_Lookup
		SetColorMaterial()

		for numIndex = 1, numAmount do

			local pEntity = g_Renderables[ numIndex ]

			if not IsValid( pEntity ) then
				continue
			end

			if IsDormant( pEntity ) then
				continue
			end

			local pEntity_t = g_Renderables_Lookup[ pEntity ]

			if pEntity_t.m_bOutsidePVS then
				continue
			end

			local vecOrigin = GetPos( pEntity )
			local angOrigin = GetAngles( pEntity )

			local vecMins, vecMaxs = GetRenderBounds( pEntity )

			if pEntity_t.m_bVisible then
				DrawWireframeBox( vecOrigin, angOrigin, vecMins, vecMaxs, COLOR_VISIBLE )
			else
				DrawWireframeBox( vecOrigin, angOrigin, vecMins, vecMaxs, COLOR_HIDDEN )
			end

		end

	end )

end
