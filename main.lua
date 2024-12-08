
if ( SERVER ) then

	util.AddNetworkString( 'env.ShareFogFarZ' )

	local ENV_FOG_FARZ
	local env_fog_controller

	timer.Create( 'env.ShareFogFarZ', engine.TickInterval() * 8, 0, function()

		if ( not IsValid( env_fog_controller ) ) then
			env_fog_controller = ents.FindByClass( 'env_fog_controller' )[1]
		else

			local farz = env_fog_controller:GetInternalVariable( 'farz' )

			if ( farz ~= ENV_FOG_FARZ ) then

				ENV_FOG_FARZ = farz

				net.Start( 'env.ShareFogFarZ' )
					net.WriteDouble( farz )
				net.Broadcast()

			end

		end

	end )

	gameevent.Listen( 'player_activate' )
	hook.Add( 'player_activate', 'env.ShareFogFarZ', function( data )

		if ( ENV_FOG_FARZ ) then

			net.Start( 'env.ShareFogFarZ' )
				net.WriteDouble( ENV_FOG_FARZ )
			net.Send( Player( data.userid ) )

		end

	end )

	return

end

local ENV_FOG_FARZ = 0

net.Receive( 'env.ShareFogFarZ', function()

	local farz = net.ReadDouble()

	if ( farz > 0 ) then
		ENV_FOG_FARZ = farz
	else
		ENV_FOG_FARZ = 0
	end

end )

--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Prepare
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
--
-- Metatables
--
local ENTITY = FindMetaTable( 'Entity' )
local VECTOR = FindMetaTable( 'Vector' )

--
-- Metamethods: Entity, Vector, Angle
--
local IsValidEntity		= ENTITY.IsValid
local IsDormant			= ENTITY.IsDormant

local GetPos			= ENTITY.GetPos
local GetRenderBounds	= ENTITY.GetRenderBounds

local IsCreatedByMap	= ENTITY.CreatedByMap

local GetNoDraw			= ENTITY.GetNoDraw

local RemoveEFlags		= ENTITY.RemoveEFlags
local AddEFlags			= ENTITY.AddEFlags


local VectorDistToSqr = VECTOR.DistToSqr


local AngleGetForward = FindMetaTable( 'Angle' ).Forward

--
-- Globals, Enums
--
local MathCos = math.cos
local DEG2RAD = math.pi / 180

local UTIL_IsPointInCone = util.IsPointInCone

local GetFogDistances			= render.GetFogDistances
local CalculatePixelVisibility	= util.PixelVisible

local tremove = table.remove


local EFL_NO_THINK_FUNCTION = EFL_NO_THINK_FUNCTION

--
-- Utilities
--
local function MacroAddCVarChangeCallback( name, callback )

	cvars.AddChangeCallback( name, function( _, _, new )

		callback( new )

	end, name )

end

local fast_isplayer do

	local getmetatable = getmetatable
	local PLAYER = FindMetaTable( 'Player' )

	function fast_isplayer( any )

		return getmetatable( any ) == PLAYER

	end

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Initialize
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
g_Renderables		= g_Renderables or { [0] = 0 }
g_RenderablesData	= g_RenderablesData or {}

hook.Add( 'EntityRemoved', 'PerformantRender_GC', function( pEntity, bFullUpdate )

	if ( bFullUpdate ) then
		return
	end

	g_RenderablesData[pEntity] = nil

end )

local g_Renderables		= g_Renderables
local g_RenderablesData = g_RenderablesData

local PERFRENDER_STATE
local PERFRENDER_CUTBEYONDFOG
local PERFRENDER_DEBUG

local RegisterPotentialRenderable
local RegisterRenderable

local SetNoDraw do

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		Purpose: Let other addons control visibility when they need to

		Note #1:
			bForcefully = true	=> Performant Render continues to control visibility
			not bForcefully		=> Performant Render no longer controls visibility
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	ENTITY.Internal_SetNoDraw = ENTITY.Internal_SetNoDraw or ENTITY.SetNoDraw
	local Internal_SetNoDraw = ENTITY.Internal_SetNoDraw

	function ENTITY:SetNoDraw( bNoDraw, bForcefully )

		if ( g_RenderablesData[self] ) then

			if ( bForcefully ~= true ) then
				g_RenderablesData[self].m_bSkipThis = true
			else
				g_RenderablesData[self].m_bSkipThis = nil
			end

		end

		Internal_SetNoDraw( self, bNoDraw )

	end

	SetNoDraw = ENTITY.SetNoDraw

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Management
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	PERFRENDER_STATE		= CreateClientConVar( 'r_performant_enable', '1', true, false, 'Enables/Disables performant rendering of props, NPCs, SENTs, etc.', 0, 1 ):GetBool()
	PERFRENDER_CUTBEYONDFOG	= CreateClientConVar( 'r_performant_cutbeyondfog', '1', true, false, 'Should we disable rendering entities that are beyond fog?', 0, 1 ):GetBool()
	PERFRENDER_DEBUG		= CreateClientConVar( 'r_performant_debug', '0', false, false, 'Enables/Disables performant render debugging.', 0, 1 ):GetBool()

	MacroAddCVarChangeCallback( 'r_performant_enable', function( new )

		PERFRENDER_STATE = tobool( new )

		if ( PERFRENDER_STATE ) then

			--
			-- In case if we have new unregistered entities
			--
			for numIndex, pEntity in ents.Iterator() do

				if ( not g_RenderablesData[pEntity] ) then
					RegisterPotentialRenderable( pEntity )
				end

			end

		else

			for numIndex = 1, g_Renderables[0] do

				local pEntity = g_Renderables[numIndex]

				if ( IsValidEntity( pEntity ) ) then

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

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Setup entities
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local CalculateDiagonal do

	--
	-- Used for fast checking whether the entity is within the reach
	--
	function CalculateDiagonal( pEntity )

		local vecMins, vecMaxs = GetRenderBounds( pEntity )
		local flDiagonalSqr = VectorDistToSqr( vecMins, vecMaxs )

		local Renderable_t = g_RenderablesData[pEntity]

		-- +15% to the squared diagonal, otherwise entities may be hidden when only one corner of an entity is visible
		Renderable_t.m_flDiagonalSqr = flDiagonalSqr * 1.3225

		Renderable_t.m_flDiagonal = flDiagonalSqr ^ 0.5

	end


	ENTITY.Internal_SetRenderBounds = ENTITY.Internal_SetRenderBounds or ENTITY.SetRenderBounds
	local Internal_SetRenderBounds = ENTITY.Internal_SetRenderBounds

	function ENTITY:SetRenderBounds( vecMins, vecMaxs, vecAdd )

		Internal_SetRenderBounds( self, vecMins, vecMaxs, vecAdd )

		if ( g_RenderablesData[self] ) then
			CalculateDiagonal( self )
		end

	end

	ENTITY.Internal_SetRenderBoundsWS = ENTITY.Internal_SetRenderBoundsWS or ENTITY.SetRenderBoundsWS
	local Internal_SetRenderBoundsWS = ENTITY.Internal_SetRenderBoundsWS

	function ENTITY:SetRenderBoundsWS( vecMins, vecMaxs, vecAdd )

		Internal_SetRenderBoundsWS( self, vecMins, vecMaxs, vecAdd )

		if ( g_RenderablesData[self] ) then
			CalculateDiagonal( self )
		end

	end

end

local CreatePixelVisibleHandle = util.GetPixelVisibleHandle

function RegisterRenderable( pEntity )

	g_RenderablesData[pEntity] = {

		m_bVisible = true;
		m_bOutsidePVS = false;
		m_PixVis = CreatePixelVisibleHandle()

	}

	CalculateDiagonal( pEntity )

	local index = g_Renderables[0]
	index = index + 1

	g_Renderables[index] = pEntity
	g_Renderables[0] = index

end

do

	--
	-- Metamethods: Entity
	--
	local GetClass = ENTITY.GetClass
	local GetOwner = ENTITY.GetOwner
	local GetModel = ENTITY.GetModel

	local IsWeapon	= ENTITY.IsWeapon
	local IsSolid	= ENTITY.IsSolid

	--
	-- Globals
	--
	local substrof = string.sub
	local isstring = isstring

	local IsValidModel = util.IsValidModel


	function RegisterPotentialRenderable( pEntity )

		if ( not IsValidEntity( pEntity ) ) then
			return
		end

		local strClass = GetClass( pEntity )

		--
		-- Compatibility: BSMod KillMoves
		--
		if ( strClass == 'ent_km_model' ) then

			local pTarget = GetOwner( pEntity )

			if ( not g_RenderablesData[pTarget] ) then
				return
			end

			for numIndex = 1, g_Renderables[0] do

				local pRenderable = g_Renderables[numIndex]

				if ( pRenderable == pTarget ) then

					SetNoDraw( pTarget, true )

					tremove( g_Renderables, numIndex )
					g_RenderablesData[pTarget] = nil

					g_Renderables[0] = g_Renderables[0] - 1

					break

				end

			end

			return

		end

		--
		-- Exclude doors
		--
		if ( substrof( strClass, 6, 9 ) == 'door' ) then
			return
		end

		--
		-- Exclude invisible entities on map load
		--
		if ( IsCreatedByMap( pEntity ) and GetNoDraw( pEntity ) ) then
			return
		end

		--
		-- Check whether the model is valid
		--
		local strModel = GetModel( pEntity )

		if ( not isstring( strModel ) ) then
			return
		end

		if ( not IsValidModel( strModel ) ) then
			return
		end

		--
		-- Exclude players, weapons, non-solid entities
		--
		if ( fast_isplayer( pEntity ) or IsWeapon( pEntity ) or ( not IsSolid( pEntity ) ) ) then
			return
		end

		RegisterRenderable( pEntity )

	end

end

hook.Add( 'OnEntityCreated', 'PerformantRender_Register', function( pEntity )

	timer.Simple( 0, function()

		RegisterPotentialRenderable( pEntity )

	end )

end )


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Visibility Calculations
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local select = select

local function CalculateRenderablesVisibility( vecViewOrigin, angViewAngles, flViewFOV )

	local g_Renderables = g_Renderables
	local numAmount = g_Renderables[0]

	if ( numAmount == 0 ) then
		return
	end

	local g_RenderablesData = g_RenderablesData

	local vecViewDirection = AngleGetForward( angViewAngles )
	local flFOVCosine = MathCos( DEG2RAD * ( flViewFOV * 0.75 ) )

	local flFogFarZSqr = ENV_FOG_FARZ * ENV_FOG_FARZ

	local PERFRENDER_CUTBEYONDFOG = PERFRENDER_CUTBEYONDFOG
	local flFogEndSqr

	if ( PERFRENDER_CUTBEYONDFOG ) then

		flFogEndSqr = select( 2, GetFogDistances() )
		flFogEndSqr = flFogEndSqr * flFogEndSqr

	end

	::reiterate::

	for numIndex = 1, numAmount do

		local pEntity = g_Renderables[numIndex]

		if ( not IsValidEntity( pEntity ) ) then

			tremove( g_Renderables, numIndex )

			numAmount = numAmount - 1
			g_Renderables[0] = numAmount

			goto reiterate

		end

		--
		-- Ignore entities outside of PVS
		--
		if ( IsDormant( pEntity ) ) then
			continue
		end

		local vecOrigin = GetPos( pEntity )

		--
		-- Ignore entities outside of FOV as the engine already hides them
		--
		if ( not UTIL_IsPointInCone( vecOrigin, vecViewOrigin, vecViewDirection, flFOVCosine, 131072 ) ) then
			continue
		end

		local Renderable_t = g_RenderablesData[pEntity]

		if ( Renderable_t.m_bSkipThis ) then
			continue
		end

		local flDiagonalSqr = Renderable_t.m_flDiagonalSqr
		local flDistSqr = VectorDistToSqr( vecViewOrigin, vecOrigin )

		--
		-- Ignore entities beyond the fog's Far Z Clip Plane
		--
		if ( flFogFarZSqr > 0 and flDistSqr > ( flFogFarZSqr + flDiagonalSqr ) ) then
			continue
		end

		--
		-- Hide entities beyond fog
		--
		local bInFog = false

		if ( PERFRENDER_CUTBEYONDFOG and flFogEndSqr > 0 ) then
			bInFog = flDistSqr > ( flFogEndSqr + flDiagonalSqr )
		end

		--
		-- Determine visibility
		--
		local bVisible = false
		local bOutsidePVS = false

		if ( bInFog ) then

			bVisible = false
			bOutsidePVS = true

		else

			local bInDistance = flDistSqr <= flDiagonalSqr
			local flRadius = Renderable_t.m_flDiagonal

			--
			-- To resolve flickering issue decreasing radius as the local player approaches
			-- Slightly increases performance loss
			--
			if ( bInDistance ) then
				flRadius = ( flRadius - ( flRadius - flDistSqr ^ 0.5 ) )
			end

			bVisible = CalculatePixelVisibility( vecOrigin, flRadius, Renderable_t.m_PixVis ) > 0

			if ( not bVisible and bInDistance ) then
				bVisible = true
			end

		end

		--
		-- Manage visibility
		--
		local bNoDraw = GetNoDraw( pEntity )

		if ( bVisible ) then

			if ( bNoDraw ) then

				SetNoDraw( pEntity, false, true )
				RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

		else

			if ( not bNoDraw ) then

				SetNoDraw( pEntity, true, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

		end

		Renderable_t.m_bVisible = bVisible
		Renderable_t.m_bOutsidePVS = bOutsidePVS

	end

end

do

	local VIEW_ORIGIN
	local VIEW_ANGLE
	local VIEW_FOV

	local MySelf = NULL

	hook.Add( 'PreRender', '!!!!!PerformantRender_Calculations', function()

		if ( not PERFRENDER_STATE ) then
			return
		end

		--
		-- Don't perform calculations while in TARDIS
		--
		if ( MySelf.tardis ) then
			return
		end

		if ( not VIEW_ORIGIN ) then
			return
		end

		CalculateRenderablesVisibility( VIEW_ORIGIN, VIEW_ANGLE, VIEW_FOV )

	end )

	hook.Add( 'RenderScene', 'PerformantRender_Calculations', function( vecViewOrigin, angViewAngles, flViewFOV )

		if ( not PERFRENDER_STATE ) then
			return
		end

		if ( not IsValidEntity( MySelf ) ) then
			MySelf = LocalPlayer()
		end

		VIEW_ORIGIN = vecViewOrigin
		VIEW_ANGLE = angViewAngles
		VIEW_FOV = flViewFOV

	end )


	--[[

		Fix for NPCs that stay/become visible after death
		The problem is that the engine internally hides a NPC just after it is killed before removing it in the next tick
		https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/ai_basenpc.cpp#L577
		https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/server/baseentity.cpp#L7089

	]]
	gameevent.Listen( 'entity_killed' )
	hook.Add( 'entity_killed', 'PerformantRender_FixVisibleDeadNPCs', function( data )

		local pNPC = Entity( data.entindex_killed )

		if ( not pNPC:IsNPC() ) then
			return
		end

		--
		-- Hide again
		--
		SetNoDraw( pNPC, true )
		RemoveEFlags( pNPC, EFL_NO_THINK_FUNCTION )

		--
		-- Unregister
		--
		for numIndex = 1, g_Renderables[0] do

			local pEntity = g_Renderables[numIndex]

			if ( pEntity == pNPC ) then

				tremove( g_Renderables, numIndex )
				g_RenderablesData[pNPC] = nil

				g_Renderables[0] = g_Renderables[0] - 1

				break

			end

		end

	end )

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Debugging
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	local COLOR_VISIBLE = Color( 0, 180, 0 )
	local COLOR_HIDDEN  = Color( 255, 50, 0 )

	local SetColorMaterial = render.SetColorMaterial
	local DrawWireframeBox = render.DrawWireframeBox

	local GetAngles = ENTITY.GetAngles

	local IS_CHEATS = GetConVar( 'sv_cheats' ):GetBool()

	MacroAddCVarChangeCallback( 'sv_cheats', function( new )

		IS_CHEATS = tobool( new )

	end )


	hook.Add( 'PostDrawTranslucentRenderables', 'PerformantRender_Debug', function( _, _, bSky )

		if ( bSky ) then
			return
		end

		if ( not ( PERFRENDER_STATE and PERFRENDER_DEBUG and IS_CHEATS ) ) then
			return
		end

		local g_Renderables = g_Renderables
		local numAmount = g_Renderables[0]

		if ( numAmount == 0 ) then
			return
		end

		local g_RenderablesData = g_RenderablesData
		SetColorMaterial()

		for numIndex = 1, numAmount do

			local pEntity = g_Renderables[numIndex]

			if ( not IsValidEntity( pEntity ) ) then
				continue
			end

			if ( IsDormant( pEntity ) ) then
				continue
			end

			local Renderable_t = g_RenderablesData[pEntity]

			if ( Renderable_t.m_bOutsidePVS ) then
				continue
			end

			local vecOrigin = GetPos( pEntity )
			local angOrigin = GetAngles( pEntity )

			local vecMins, vecMaxs = GetRenderBounds( pEntity )

			if ( Renderable_t.m_bVisible ) then
				DrawWireframeBox( vecOrigin, angOrigin, vecMins, vecMaxs, COLOR_VISIBLE )
			else
				DrawWireframeBox( vecOrigin, angOrigin, vecMins, vecMaxs, COLOR_HIDDEN )
			end

		end

	end )

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Performant Render: Compatibility
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local function ShowRenderablesInFOV( bShow, vecViewOrigin, angViewAngles, flViewFOV )

	local g_Renderables = g_Renderables
	local g_RenderablesData = g_RenderablesData

	local vecViewDirection = bShow and AngleGetForward( angViewAngles ) or nil
	local flFOVCosine = bShow and MathCos( DEG2RAD * ( flViewFOV * 0.75 ) ) or nil

	for numIndex = 1, g_Renderables[0] do

		local pEntity = g_Renderables[numIndex]

		if ( not IsValidEntity( pEntity ) ) then
			continue
		end

		if ( IsDormant( pEntity ) ) then
			continue
		end

		local Renderable_t = g_RenderablesData[pEntity]
		local bVisible = Renderable_t.m_bVisible

		if ( not bVisible and not Renderable_t.m_bSkipThis ) then

			if ( bShow ) then

				local vecOrigin = GetPos( pEntity )

				if ( not UTIL_IsPointInCone( vecOrigin, vecViewOrigin, vecViewDirection, flFOVCosine, 131072 ) ) then
					continue
				end

				SetNoDraw( pEntity, false, true )
				RemoveEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			else

				SetNoDraw( pEntity, true, true )
				AddEFlags( pEntity, EFL_NO_THINK_FUNCTION )

			end

		end

	end

end

do -- with RT Cameras

	render.Internal_RenderView = render.Internal_RenderView or render.RenderView
	local Internal_RenderView = render.Internal_RenderView

	local GetViewSetup = render.GetViewSetup

	function render.RenderView( ViewData_t )

		if ( PERFRENDER_STATE ) then

			local ViewSetup_t = GetViewSetup()

			local vecViewOrigin	= ViewData_t.origin or ViewSetup_t.origin
			local angViewAngles	= ViewData_t.angles or ViewSetup_t.angles
			local flViewFOV		= ViewData_t.fov or ViewSetup_t.fov

			ShowRenderablesInFOV( true, vecViewOrigin, angViewAngles, flViewFOV )

				Internal_RenderView( ViewData_t )

			ShowRenderablesInFOV( false )

			return

		end

		Internal_RenderView( ViewData_t )

	end

end
