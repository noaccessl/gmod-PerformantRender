--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––

	De-renders objects obstructed yet in FOV & drawn.

	Find on GitHub: https://github.com/noaccessl/gmod-PerformantRender
	Get on Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3105962404

–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	The serverside part
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
if ( SERVER ) then

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		Purpose: If 3D Skybox is absent, mark this for the clients
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	hook.Add( 'InitPostEntity', 'PerformantRender:Check3DSky', function()

		hook.Remove( 'InitPostEntity', 'PerformantRender:Check3DSky' )

		if ( #ents.FindByClass( 'sky_camera' ) == 0 ) then
			SetGlobal2Bool( 'PerformantRender:No3DSky', true )
		end

	end )

	-- Return. The next code is clientside.
	return

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Prepare
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
--
-- Metatables
--
local CEntity = FindMetaTable( 'Entity' )
local CVector = FindMetaTable( 'Vector' )
local CAngle = FindMetaTable( 'Angle' )

--
-- Common Hot Functions
--
local GetRenderBounds = CEntity.GetRenderBounds

local VectorDistance = CVector.Distance
local VectorCopy = CVector.Set

local Vector = Vector

local UTIL_TimerCycle = util.TimerCycle

local CurTime = CurTime



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	(Internal) GetFarZ
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local function GetFarZ() return render.GetViewSetup().zfar end

--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	(Internal, Aux) QuickCVarChangeCallback
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local function QuickCVarChangeCallback( name, valuetype, writefield, fnCallback )

	local pfnConverter = _G['to' .. valuetype]

	cvars.AddChangeCallback( name, function( _, _, value )

		value = pfnConverter( value )

		if ( writefield ) then
			PerformantRender[writefield] = value
		end

		if ( fnCallback ) then
			fnCallback( value )
		end

	end, 'PerformantRender' )

end

--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	(Internal) fast_isplayer, fast_isweapon
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local fast_isplayer, fast_isweapon; do

	local getmetatable = getmetatable

	local g_pPlayerMetaTable = FindMetaTable( 'Player' )
	function fast_isplayer( any ) return getmetatable( any ) == g_pPlayerMetaTable end

	local g_pWeaponMetaTable = FindMetaTable( 'Weapon' )
	function fast_isweapon( any ) return getmetatable( any ) == g_pWeaponMetaTable end

end

--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	(Internal, Debug) ConMsg
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
local ConMsg; do

	local MsgC = MsgC
	local Format = string.format
	local color_white = color_white
	function ConMsg( str, ... ) MsgC( color_white, Format( str, ... ) ) end

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Setup
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
--
-- ConVars
--
local performantrender_enable = CreateConVar( 'performantrender_enable', '1', FCVAR_ARCHIVE, 'Enable Performant Render?', 0, 1 )

local performantrender_debug = CreateConVar( 'performantrender_debug', '0', FCVAR_NONE, 'Enable Performant Render Debug Mode?', 0, 1 )
local performantrender_debug_spew = CreateConVar( 'performantrender_debug_spew', '0', FCVAR_NONE, 'Output additional info to the console?', 0, 1 )
local performantrender_debug_boxes = CreateConVar( 'performantrender_debug_boxes', '1', FCVAR_NONE, 'Draw wireframe boxes of renderables? Requires sv_cheats.', 0, 1 )
local performantrender_debug_squares = CreateConVar( 'performantrender_debug_squares', '0', FCVAR_NONE, 'Draw approximate pixel-visibility-test squares? Requires sv_cheats.', 0, 1 )

--
-- Worktable
--
PerformantRender = PerformantRender or {}
do

	PerformantRender.m_bLocked = false
	do

		timer.Create( 'PerformantRender:Lock', 0.15, 0, function()

			PerformantRender.m_bLocked = ( not system.HasFocus() )

		end )

	end

	PerformantRender.m_bState = performantrender_enable:GetBool()

	PerformantRender.m_bDebug = performantrender_debug:GetBool()
	PerformantRender.m_Debug_bSpew = performantrender_debug_spew:GetBool()
	PerformantRender.m_Debug_bBoxes = performantrender_debug_boxes:GetBool()
	PerformantRender.m_Debug_bSquares = performantrender_debug_squares:GetBool()

	PerformantRender.m_bPlayerValid = false
	PerformantRender.g_pPlayer = PerformantRender.g_pPlayer or LocalPlayer()
	do

		local function CreatePlayerDataProxy()

			PerformantRender.m_hPlayerData = newproxy()
			debug.setmetatable( PerformantRender.m_hPlayerData, {

				__tostring = function( self ) return Format( 'PerformantRenderPlayerDataProxy: %p', self ) end;
				__index = CEntity.GetTable( PerformantRender.g_pPlayer )

			} )

		end

		if ( not IsValid( PerformantRender.g_pPlayer ) ) then

			hook.Add( 'InitPostEntity', 'PerformantRender:GetLocalPlayer', function()

				hook.Remove( 'InitPostEntity', 'PerformantRender:GetLocalPlayer' )

				PerformantRender.m_bPlayerValid = true
				PerformantRender.g_pPlayer = LocalPlayer()

				CreatePlayerDataProxy()

			end )

		else

			PerformantRender.m_bPlayerValid = true

			if ( not PerformantRender.m_hPlayerData ) then
				CreatePlayerDataProxy()
			end

		end

	end

	PerformantRender.g_vecViewOrigin = Vector( 0, 0, 0 )
	PerformantRender.m_vecViewOriginAdd = Vector( 0, 0, 0 )

	PerformantRender.g_vecViewDirection = Vector( 0, 0, 0 )

	PerformantRender.g_flFOVCosine = 0

	PerformantRender.g_flFarZ = GetFarZ()
	do

		timer.Create( 'PerformantRender:UpdateFarZ', 0.3, 0, function()

			PerformantRender.g_flFarZ = GetFarZ()

		end )

	end

	PerformantRender.g_bRender3DSky = GetConVar( 'r_3dsky' ):GetBool()
	PerformantRender.g_bNo3DSky = PerformantRender.g_bNo3DSky

	PerformantRender.m_RenderablesList = PerformantRender.m_RenderablesList or { [0] = 0 } -- (bidirectional).
	PerformantRender.m_RenderablesData = PerformantRender.m_RenderablesData or {}

end

local SKYBOXTEST_DELAY = 0.75
local SKYBOXTEST_DELAY_PERSONALMUL = 0.075

--
-- ConVars Change Callbacks
--
do

	-- [[ performantrender_enable ]] --

	QuickCVarChangeCallback( 'performantrender_enable', 'bool', 'm_bState', function( bState )

		if ( not bState ) then

			for i, pEntity in ipairs( PerformantRender.m_RenderablesList ) do
				PerformantRender:Derender( pEntity, false )
			end

		end

	end )

	-- [[ performantrender_debug ]] --

	QuickCVarChangeCallback( 'performantrender_debug', 'bool', 'm_bDebug' )

	-- [[ performantrender_debug_spew ]] --

	QuickCVarChangeCallback( 'performantrender_debug_spew', 'bool', 'm_Debug_bSpew' )

	-- [[ performantrender_debug_boxes ]] --

	QuickCVarChangeCallback( 'performantrender_debug_boxes', 'bool', 'm_Debug_bBoxes' )

	-- [[ performantrender_debug_squares ]] --

	QuickCVarChangeCallback( 'performantrender_debug_squares', 'bool', 'm_Debug_bSquares' )

	-- [[ r_3dsky ]] --

	QuickCVarChangeCallback( 'r_3dsky', 'bool', 'g_bRender3DSky' )

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Registration
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		(Internal) PerformantRender_CalcPixVisSquareSize
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local function PerformantRender_CalcPixVisSquareSize( pEntity, renderable_t )

		renderable_t = renderable_t or PerformantRender.m_RenderablesData[pEntity]

		if ( not renderable_t ) then
			return
		end

		local vecMins, vecMaxs = GetRenderBounds( pEntity )

		local flDiagonal = VectorDistance( vecMins, vecMaxs )
		renderable_t.m_flPixVisSquareSize = ( flDiagonal * 0.5 ) * 1.33
		-- +33% bonus of margin to the pixel visiblity square size.

		if ( PerformantRender.m_bDebug and PerformantRender.m_Debug_bBoxes ) then

			renderable_t.m_Debug_vecRenderBoundsMins = renderable_t.m_Debug_vecRenderBoundsMins or Vector( 0, 0, 0 )
			VectorCopy( renderable_t.m_Debug_vecRenderBoundsMins, vecMins )

			renderable_t.m_Debug_vecRenderBoundsMaxs = renderable_t.m_Debug_vecRenderBoundsMaxs or Vector( 0, 0, 0 )
			VectorCopy( renderable_t.m_Debug_vecRenderBoundsMaxs, vecMaxs )

		end

	end

	-- Integrate into Entity:SetRenderBounds & Entity:SetRenderBoundsWS
	do

		CEntity.SetRenderBoundsEx = CEntity.SetRenderBoundsEx or CEntity.SetRenderBounds
		local SetRenderBoundsEx = CEntity.SetRenderBoundsEx

		function CEntity:SetRenderBounds( vecMins, vecMaxs, vecAdd )

			SetRenderBoundsEx( self, vecMins, vecMaxs, vecAdd )

			PerformantRender_CalcPixVisSquareSize( self )

		end

		CEntity.SetRenderBoundsWSEx = CEntity.SetRenderBoundsWSEx or CEntity.SetRenderBoundsWS
		local SetRenderBoundsWSEx = CEntity.SetRenderBoundsWSEx

		function CEntity:SetRenderBoundsWS( vecMins, vecMaxs, vecAdd )

			SetRenderBoundsWSEx( self, vecMins, vecMaxs, vecAdd )

			PerformantRender_CalcPixVisSquareSize( self )

		end

	end

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		(Internal) PerformantRender_NewRenderableDatum
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local UTIL_GetPixelVisibleHandle = util.GetPixelVisibleHandle

	local function PerformantRender_NewRenderableDatum()

		local renderable_t = {

			m_bDerendered;

			m_iLastRenderMode;
			m_tLastColor = { true; true; true; true };

			m_bDormant;

			m_Save_vecAbsCenter;

			m_bInSkybox;
			-- Bear in mind, the test is happening against vecViewOrigin.
			-- So it'll be false if vecViewOrigin is too in the skybox.
			m_iNextSkyboxTest = 0;

			m_bOutOfFOV;

			m_pPixVisHandle = UTIL_GetPixelVisibleHandle();
			m_flPixVisSquareSize;
			m_flVisibility;

			m_bOmitted;

			m_Debug_vecAbsOrigin;
			m_Debug_angAbsRotation;
			m_Debug_vecRenderBoundsMins;
			m_Debug_vecRenderBoundsMaxs;
			m_Debug_flTotalSquareSize

		}

		return renderable_t

	end

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		RegisterRenderable
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	function PerformantRender:RegisterRenderable( pEntity )

		local renderable_t = PerformantRender_NewRenderableDatum()

		PerformantRender_CalcPixVisSquareSize( pEntity, renderable_t )

		local pRenderablesList = self.m_RenderablesList

		local i = pRenderablesList[0] + 1
		pRenderablesList[i] = pEntity
		pRenderablesList[pEntity] = i
		pRenderablesList[0] = i

		self.m_RenderablesData[pEntity] = renderable_t

	end

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		TryPotentialRenderable
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local GetClass = CEntity.GetClass
	local strfind = string.find
	local GetNoDraw = CEntity.GetNoDraw
	local IsScripted = CEntity.IsScripted
	local GetModel = CEntity.GetModel
	local UTIL_IsValidModel = util.IsValidModel

	function PerformantRender:TryPotentialRenderable( pEntity )

		-- Exclude players
		if ( fast_isplayer( pEntity ) ) then return end

		-- Exclude weapons
		if ( fast_isweapon( pEntity ) ) then return end

		local classname = GetClass( pEntity )

		-- Exclude viewmodels
		if ( classname == 'viewmodel' ) then return end

		-- Exclude effects
		if ( classname == 'class CLuaEffect' ) then return end

		-- Exclude clientside props
		if ( classname == 'class C_PhysPropClientside' ) then return end

		-- Exclude doors
		if ( strfind( classname, 'door' ) ) then return end

		-- Exclude nodraws
		if ( GetNoDraw( pEntity ) ) then return end

		-- Let's not mess with SENTs
		if ( IsScripted( pEntity ) ) then return end

		--
		-- Model validity check
		--
		local mdl = GetModel( pEntity )

		if ( not mdl ) then return end
		if ( not UTIL_IsValidModel( mdl ) ) then return end

		self:RegisterRenderable( pEntity )

	end

	--
	-- Integrate
	--
	hook.Add( 'OnEntityCreated', 'PerformantRender:TryPotentialRenderable', function( pEntity )

		PerformantRender:TryPotentialRenderable( pEntity )

	end )

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Data, data, data
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		UpdateLocalData1
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local GetVelocity = CEntity.GetVelocity
	local VectorMultiply, FrameTime = CVector.Mul, FrameTime

	function PerformantRender:UpdateLocalData1()

		if ( self.m_bLocked ) then return end
		if ( not self.m_bState ) then return end

		if ( self.m_bPlayerValid ) then

			local vecViewOriginAdd = self.m_vecViewOriginAdd

			VectorCopy( vecViewOriginAdd, GetVelocity( self.g_pPlayer ) )
			VectorMultiply( vecViewOriginAdd, FrameTime() )

			if ( self.g_bNo3DSky == nil ) then
				self.g_bNo3DSky = GetGlobal2Bool( 'PerformantRender:No3DSky' )
			end

		end

	end

	--
	-- Integrate
	--
	hook.Add( 'Tick', 'PerformantRender:UpdateLocalData1', function()

		PerformantRender:UpdateLocalData1()

	end )

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		UpdateLocalData2
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local VectorAdd = CVector.Add
	local AngleForward = CAngle.Forward
	local cos, rad = math.cos, math.rad

	function PerformantRender:UpdateLocalData2( vecViewOrigin, angViewDirection, flViewFOV )

		if ( self.m_bLocked ) then return end
		if ( not self.m_bState ) then return end

		VectorAdd( vecViewOrigin, self.m_vecViewOriginAdd ) -- Quick interpolation of sorts
		VectorCopy( self.g_vecViewOrigin, vecViewOrigin )

		VectorCopy( self.g_vecViewDirection, AngleForward( angViewDirection ) )

		self.g_flFOVCosine = cos( rad( flViewFOV ) )

	end

	--
	-- Integrate
	--
	hook.Add( 'RenderScene', 'PerformantRender:UpdateLocalData2', function( vecViewOrigin, angViewDirection, flViewFOV )

		PerformantRender:UpdateLocalData2( vecViewOrigin, angViewDirection, flViewFOV )

	end )

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		UpdateRenderablesData
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local IsDormant = CEntity.IsDormant
	local WorldSpaceCenter = CEntity.WorldSpaceCenter
	local UTIL_TraceLine = util.TraceLine
	local UTIL_IsPointInCone = util.IsPointInCone
	local UTIL_PixelVisible = util.PixelVisible

	local GetPos, Angle, AngleCopy, GetAngles = CEntity.GetPos, Angle, CAngle.Set, CEntity.GetAngles

	local g_traceSkyboxTest_t = {}
	local g_traceSkyboxTest = {

		start = Vector();
		endpos = Vector();

		filter = { true };

		mask = MASK_SOLID_BRUSHONLY;
		collisiongroup = COLLISION_GROUP_DEBRIS;

		output = g_traceSkyboxTest_t

	}
	-- Quite very simple skybox test setup

	local g_traceSkyboxTest_start = g_traceSkyboxTest.start
	local g_traceSkyboxTest_endpos = g_traceSkyboxTest.endpos
	local g_traceSkyboxTest_filter = g_traceSkyboxTest.filter

	function PerformantRender:UpdateRenderablesData()

		if ( self.m_bLocked ) then return end
		if ( not self.m_bState ) then return end

		local bDebug = self.m_bDebug
		local bDebugSpew = ( bDebug and self.m_Debug_bSpew )
		local bDebugBoxes = ( bDebug and self.m_Debug_bBoxes )
		local bDebugSquares = ( bDebug and self.m_Debug_bSquares )

		if ( bDebugSpew ) then UTIL_TimerCycle() end

		local pRenderablesList = self.m_RenderablesList
		local numRenderables = pRenderablesList[0]

		if ( numRenderables == 0 ) then
			return
		end

		local pRenderablesData = self.m_RenderablesData

		local bPerformSkyboxTest = ( self.g_bRender3DSky and not self.g_bNo3DSky )
		local flCurTime

		local vecViewOrigin = self.g_vecViewOrigin

		if ( bPerformSkyboxTest ) then

			flCurTime = CurTime()
			VectorCopy( g_traceSkyboxTest_endpos, vecViewOrigin )

		end

		local vecViewDirection = self.g_vecViewDirection
		local flFOVCosine = self.g_flFOVCosine

		local flFarZ = self.g_flFarZ

		for i = 1, numRenderables do

			local pEntity = pRenderablesList[i]
			local renderable_t = pRenderablesData[pEntity]

			if ( renderable_t.m_bOmitted ) then
				continue
			end

			local bDormant = IsDormant( pEntity )
			renderable_t.m_bDormant = bDormant

			if ( bDormant ) then
				continue
			end

			local vecAbsCenter = WorldSpaceCenter( pEntity )
			renderable_t.m_Save_vecAbsCenter = vecAbsCenter

			local bInSkybox = renderable_t.m_bInSkybox

			if ( bPerformSkyboxTest ) then

				local iNextSkyboxTest = renderable_t.m_iNextSkyboxTest

				if ( iNextSkyboxTest < flCurTime ) then

					VectorCopy( g_traceSkyboxTest_start, vecAbsCenter )
					g_traceSkyboxTest_filter[1] = pEntity

					UTIL_TraceLine( g_traceSkyboxTest )

					bInSkybox = g_traceSkyboxTest_t.HitSky
					renderable_t.m_bInSkybox = bInSkybox

					renderable_t.m_iNextSkyboxTest = ( flCurTime + SKYBOXTEST_DELAY + ( i - 1 ) * SKYBOXTEST_DELAY_PERSONALMUL )

				end

			else

				bInSkybox = nil
				renderable_t.m_bInSkybox = nil

			end

			if ( bInSkybox ) then

				-- Not doing any checks further at this point, leaving stuff to the engine.

				renderable_t.m_flVisibility = 1
				continue

			end

			local flPixVisSquareSize = renderable_t.m_flPixVisSquareSize

			local bOutOfFOV = ( not UTIL_IsPointInCone( vecAbsCenter, vecViewOrigin, vecViewDirection, flFOVCosine, flFarZ + flPixVisSquareSize ) )
			renderable_t.m_bOutOfFOV = bOutOfFOV

			if ( bOutOfFOV ) then
				continue
			end

			local flDistance = VectorDistance( vecViewOrigin, vecAbsCenter )
			local bWithinReach = ( flDistance <= flPixVisSquareSize * 1.33 )
			-- 33% bonus of margin to the local proximity.
			-- Yeah, adding to the square size just in place.

			if ( bWithinReach ) then
				flPixVisSquareSize = ( flPixVisSquareSize - ( flPixVisSquareSize - flDistance ) )
			end

			local flVisibility = UTIL_PixelVisible( vecAbsCenter, flPixVisSquareSize, renderable_t.m_pPixVisHandle )

			if ( bWithinReach and flVisibility == 0 ) then
				flVisibility = 1
			end

			renderable_t.m_flVisibility = flVisibility

			if ( bDebugBoxes ) then

				renderable_t.m_Debug_vecAbsOrigin = renderable_t.m_Debug_vecAbsOrigin or Vector( 0, 0, 0 )
				VectorCopy( renderable_t.m_Debug_vecAbsOrigin, GetPos( pEntity ) )

				renderable_t.m_Debug_angAbsRotation = renderable_t.m_Debug_angAbsRotation or Angle( 0, 0, 0 )
				AngleCopy( renderable_t.m_Debug_angAbsRotation, GetAngles( pEntity ) )

			end

			if ( bDebugSquares ) then
				renderable_t.m_Debug_flTotalSquareSize = flPixVisSquareSize
			end

		end

		if ( bDebugSpew ) then
			ConMsg( 'PerformantRender:UpdateRenderablesData() took ~%.4f ms\n', UTIL_TimerCycle() )
		end

	end

	--
	-- Integrate
	--
	hook.Add( 'PostRender', 'PerformantRender:UpdateRenderablesData', function()

		PerformantRender:UpdateRenderablesData()

	end )

end


--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	De-rendering
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		Derender
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local GetRenderMode = CEntity.GetRenderMode
	local GetColor4Part = CEntity.GetColor4Part
	local SetRenderMode = CEntity.SetRenderMode
	local SetColor4Part = CEntity.SetColor4Part
	local AddEffects = CEntity.AddEffects
	local RemoveEffects = CEntity.RemoveEffects

	local RENDERMODE_NONE = RENDERMODE_NONE
	local EF_DERENDERED = bit.bor( EF_NOSHADOW, EF_NORECEIVESHADOW, EF_NOFLASHLIGHT )

	function PerformantRender:Derender( pEntity, bDerender, renderable_t )

		renderable_t = renderable_t or self.m_RenderablesData[pEntity]

		if ( bDerender ) then

			if ( not renderable_t.m_bDerendered ) then

				renderable_t.m_iLastRenderMode = GetRenderMode( pEntity )

				local r, g, b, a = GetColor4Part( pEntity )

				local ptLastColor = renderable_t.m_tLastColor
				ptLastColor[1], ptLastColor[2], ptLastColor[3], ptLastColor[4] = r, g, b, a

				SetRenderMode( pEntity, RENDERMODE_NONE )
				SetColor4Part( pEntity, 255, 255, 255, 0 )
				AddEffects( pEntity, EF_DERENDERED )

				renderable_t.m_bDerendered = true

			end

			return

		end

		if ( renderable_t.m_bDerendered ) then

			local ptLastColor = renderable_t.m_tLastColor

			SetRenderMode( pEntity, renderable_t.m_iLastRenderMode )
			SetColor4Part( pEntity, ptLastColor[1], ptLastColor[2], ptLastColor[3], ptLastColor[4] )
			RemoveEffects( pEntity, EF_DERENDERED )

			renderable_t.m_bDerendered = false

		end

	end

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		PerformDerendering
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	function PerformantRender:PerformDerendering()

		if ( self.m_bLocked ) then return end
		if ( not self.m_bState ) then return end

		-- Don't perform de-rendering while in TARDIS
		if ( self.m_hPlayerData.tardis ) then
			return
		end

		local bDebugSpew = ( self.m_bDebug and self.m_Debug_bSpew )

		if ( bDebugSpew ) then UTIL_TimerCycle() end

		local pRenderablesList = self.m_RenderablesList
		local numRenderables = pRenderablesList[0]

		if ( numRenderables == 0 ) then
			return
		end

		local pRenderablesData = self.m_RenderablesData

		for i = 1, numRenderables do

			local pEntity = pRenderablesList[i]
			local renderable_t = pRenderablesData[pEntity]

			if ( renderable_t.m_bOmitted or renderable_t.m_bDormant or renderable_t.m_bOutOfFOV ) then
				continue
			end

			self:Derender( pEntity, renderable_t.m_flVisibility == 0, renderable_t )

		end

		if ( bDebugSpew ) then
			ConMsg( 'PerformantRender:PerformDerendering() took ~%.4f ms\n---\n', UTIL_TimerCycle() )
		end

	end

	--
	-- Integrate
	--
	hook.Add( 'PreRender', 'PerformantRender:PerformDerendering', function()

		PerformantRender:PerformDerendering()

	end )

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Compatibility: render.RenderView
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	render.RenderViewEx = render.RenderViewEx or render.RenderView

	local PerformantRender = PerformantRender
	local AngleForward = CAngle.Forward
	local cos, rad = math.cos, math.rad
	local UTIL_IsPointInCone = util.IsPointInCone
	local Derender = PerformantRender.Derender

	local RenderViewEx = render.RenderViewEx

	function render.RenderView( view )

		-- Show renderables for this view
		do

			if ( PerformantRender.m_bLocked or not PerformantRender.m_bState ) then
				goto vanilla
			end

			if ( not view ) then
				goto vanilla
			end

			if ( view and not ( view.origin and view.angles and view.fov ) ) then
				goto vanilla
			end

			local pRenderablesList = PerformantRender.m_RenderablesList
			local numRenderables = pRenderablesList[0]

			if ( numRenderables == 0 ) then
				goto vanilla
			end

			local pRenderablesData = PerformantRender.m_RenderablesData

			local vecViewOrigin
			local vecViewDirection
			local flFOVCosine
			local flFarZ

			vecViewOrigin = view.origin

			if ( not vecViewOrigin ) then
				vecViewOrigin = PerformantRender.g_vecViewOrigin
			end

			local angViewDirection = view.angles

			if ( angViewDirection ) then
				vecViewDirection = AngleForward( angViewDirection )
			else
				vecViewDirection = PerformantRender.g_vecViewDirection
			end

			local flFOV = view.fov

			if ( flFOV ) then
				flFOVCosine = cos( rad( flFOV ) )
			else
				flFOVCosine = PerformantRender.g_flFOVCosine
			end

			flFarZ = view.zfar

			if ( not flFarZ ) then
				flFarZ = PerformantRender.g_flFarZ
			end

			for i = 1, numRenderables do

				local pEntity = pRenderablesList[i]
				local renderable_t = pRenderablesData[pEntity]

				if ( renderable_t.m_bInSkybox ) then
					continue
				end

				local vecAbsCenter = renderable_t.m_Save_vecAbsCenter

				if ( not vecAbsCenter ) then
					-- Wait for the value
					continue
				end

				if ( UTIL_IsPointInCone( vecAbsCenter, vecViewOrigin, vecViewDirection, flFOVCosine, flFarZ + renderable_t.m_flPixVisSquareSize ) ) then
					Derender( nil, pEntity, false, renderable_t )
				end

			end

		end

		::vanilla::
		RenderViewEx( view )

	end

end

--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Compatibility: point_camera
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	local PerformantRender = PerformantRender

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		Storage
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	PerformantRender.g_PointCamerasList = PerformantRender.g_PointCamerasList or {}
	do

		local GetClass = CEntity.GetClass

		hook.Add( 'OnEntityCreated', 'PerformantRender:PointCamerasCompat', function( pEntity )

			if ( GetClass( pEntity ) == 'point_camera' ) then
				table.insert( PerformantRender.g_PointCamerasList, pEntity )
			end

		end )

		hook.Add( 'EntityRemoved', 'PerformantRender:PointCamerasCompat', function( pEntity, bFullUpdate )

			if ( bFullUpdate ) then
				return
			end

			if ( GetClass( pEntity ) == 'point_camera' ) then
				table.RemoveByValue( PerformantRender.g_PointCamerasList, pEntity )
			end

		end )

	end

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		Purpose: Show renderables for point cameras
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local GetInternalVariable = CEntity.GetInternalVariable
	local IsDormant = CEntity.IsDormant
	local GetPos = CEntity.GetPos
	local GetAngles = CEntity.GetAngles
	local cos, rad = math.cos, math.rad
	local UTIL_IsPointInCone = util.IsPointInCone
	local Derender = PerformantRender.Derender

	hook.Add( 'DrawMonitors', 'PerformantRender:PointCamerasCompat', function()

		if ( PerformantRender.m_bLocked or not PerformantRender.m_bState ) then
			return
		end

		local pRenderablesList = PerformantRender.m_RenderablesList
		local numRenderables = pRenderablesList[0]

		if ( numRenderables == 0 ) then
			return
		end

		local pRenderablesData = PerformantRender.m_RenderablesData

		local pPointCamerasList = PerformantRender.g_PointCamerasList
		local numCameras = #pPointCamerasList

		if ( numCameras == 0 ) then
			return
		end

		local flFarZ = PerformantRender.g_flFarZ

		for i_camera = 1, numCameras do

			local pPointCamera = pPointCamerasList[i_camera]

			if ( not GetInternalVariable( pPointCamera, 'm_bActive' ) or IsDormant( pPointCamera ) ) then
				continue
			end

			local vecViewOrigin = GetPos( pPointCamera )
			local vecViewDirection = GetAngles( pPointCamera )
			local flFOVCosine = cos( rad( GetInternalVariable( pPointCamera, 'm_FOV' ) ) )

			for i_renderable = 1, numRenderables do

				local pEntity = pRenderablesList[i_renderable]
				local renderable_t = pRenderablesData[pEntity]

				if ( renderable_t.m_bInSkybox ) then
					continue
				end

				if ( UTIL_IsPointInCone( renderable_t.m_Save_vecAbsCenter, vecViewOrigin, vecViewDirection, flFOVCosine, flFarZ + renderable_t.m_flPixVisSquareSize ) ) then
					Derender( nil, pEntity, false, renderable_t )
				end

			end

		end

	end )

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Garbage Collection
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		RemoveRenderable
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local pixelvis_handle_gc = FindMetaTable( 'pixelvis_handle_t' ).__gc
	local next = next
	local tableremove = table.remove

	function PerformantRender:RemoveRenderable( pEntity )

		local pRenderablesData = self.m_RenderablesData
		local renderable_t = pRenderablesData[pEntity]

		if ( not renderable_t ) then
			return
		end

		-- "Remove" the pixel visibility handle
		pixelvis_handle_gc( renderable_t.m_pPixVisHandle )

		--
		-- Empty the datum
		--
		local ptLastColor = renderable_t.m_tLastColor
		ptLastColor[1], ptLastColor[2], ptLastColor[3], ptLastColor[4], ptLastColor = nil

		for k in next, renderable_t do renderable_t[k] = nil end

		renderable_t = nil

		-- Remove from the data
		pRenderablesData[pEntity] = nil

		--
		-- Remove from the list
		--
		local pRenderablesList = self.m_RenderablesList

		local i = pRenderablesList[pEntity]

		pRenderablesList[tableremove( pRenderablesList, i )] = nil

		local numRenderables = pRenderablesList[0] - 1
		pRenderablesList[0] = numRenderables

		--
		-- Update indexes
		--
		if ( i <= numRenderables ) then

			::update_index::

				pRenderablesList[pRenderablesList[i]] = i

			if ( i ~= numRenderables ) then i = i + 1; goto update_index end

		end

	end

	--
	-- Integrate
	--
	hook.Add( 'EntityRemoved', 'PerformantRender:RemoveRenderable', function( pEntity )

		PerformantRender:RemoveRenderable( pEntity )

	end )

end



--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
	Debugging
–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
do

	local g_bIsCheats = GetConVar( 'sv_cheats' ):GetBool()
	QuickCVarChangeCallback( 'sv_cheats', 'bool', nil, function( bIsCheats ) g_bIsCheats = bIsCheats end )

	local COLOR_VISIBLE = Color( 224, 225, 221 )
	local COLOR_DERENDERED = Color( 13, 27, 42 )

	local MATERIAL_DEBUG = CreateMaterial(
		'performantrender/debug',
		'Wireframe_DX9',
		{

			['$basetexture'] = 'color/white',
			['$vertexcolor'] = 1;
			['$ignorez'] = 1;

		}
	)

	--[[–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
		DrawDebug
	–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––]]
	local SetMaterial = render.SetMaterial
	local DrawWireframeBox = render.DrawWireframeBox
	local DrawSprite = render.DrawSprite

	function PerformantRender:DrawDebug()

		if ( self.m_bLocked ) then return end
		if ( not self.m_bState ) then return end
		if ( not self.m_bDebug ) then return end
		if ( not g_bIsCheats ) then return end

		local bDebugBoxes = self.m_Debug_bBoxes
		local bDebugSquares = self.m_Debug_bSquares

		if ( not bDebugBoxes and not bDebugSquares ) then
			return
		end

		local pRenderablesList = self.m_RenderablesList
		local numRenderables = pRenderablesList[0]

		if ( numRenderables == 0 ) then
			return
		end

		local pRenderablesData = self.m_RenderablesData

		SetMaterial( MATERIAL_DEBUG )

		for i = 1, numRenderables do

			local pEntity = pRenderablesList[i]
			local renderable_t = pRenderablesData[pEntity]

			if ( renderable_t.m_bOmitted or renderable_t.m_bDormant or renderable_t.m_bInSkybox or renderable_t.m_bOutOfFOV ) then
				continue
			end

			local colState

			local vecAbsOrigin = renderable_t.m_Debug_vecAbsOrigin

			if ( bDebugBoxes and vecAbsOrigin ) then

				colState = ( renderable_t.m_bDerendered and COLOR_DERENDERED or COLOR_VISIBLE )

				local angAbsRotation = renderable_t.m_Debug_angAbsRotation

				local vecRenderBoundsMins = renderable_t.m_Debug_vecRenderBoundsMins
				local vecRenderBoundsMaxs

				-- In case these're missing
				if ( not vecRenderBoundsMins ) then

					vecRenderBoundsMins, vecRenderBoundsMaxs = GetRenderBounds( pEntity )
					renderable_t.m_Debug_vecRenderBoundsMins, renderable_t.m_Debug_vecRenderBoundsMaxs = vecRenderBoundsMins, vecRenderBoundsMaxs

				end

				vecRenderBoundsMaxs = vecRenderBoundsMaxs or renderable_t.m_Debug_vecRenderBoundsMaxs

				DrawWireframeBox(
					vecAbsOrigin,
					angAbsRotation,
					vecRenderBoundsMins,
					vecRenderBoundsMaxs,
					colState
				)

			end

			local vecAbsCenter = renderable_t.m_Save_vecAbsCenter

			if ( bDebugSquares and vecAbsCenter ) then

				colState = colState or ( renderable_t.m_bDerendered and COLOR_DERENDERED or COLOR_VISIBLE )

				local size = renderable_t.m_Debug_flTotalSquareSize

				if ( size ) then

					DrawSprite(
						vecAbsCenter,
						size,
						size,
						colState
					)

				end

			end

		end

	end

	--
	-- Integrate
	--
	hook.Add( 'PostDrawTranslucentRenderables', 'PerformantRender:DrawDebug', function( bDepth, _, b3DSky )

		if ( bDepth or b3DSky ) then
			return
		end

		PerformantRender:DrawDebug()

	end )

end
