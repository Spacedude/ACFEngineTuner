TOOL.Category		= "Construction"
TOOL.Name			= "#Tool.acfenginetuner.listname"
TOOL.Author 		= "Spacecode"
TOOL.Command		= nil
TOOL.ConfigName		= ""

TOOL.ClientConVar[ "PeakTorque" ]	= 100
TOOL.ClientConVar[ "LimitRPM" ]		= 7000
TOOL.ClientConVar[ "IdleRPM" ]		= 900
TOOL.ClientConVar[ "PeakMinRPM" ]	= 4000
TOOL.ClientConVar[ "PeakMaxRPM" ]	= 6000
TOOL.ClientConVar[ "flywheelmass" ]	= 1
TOOL.ClientConVar[ "SoundPitch" ]	= 1

if CLIENT then
	language.Add( "Tool.acfenginetuner.listname", "ACF engine tuner" )
	language.Add( "Tool.acfenginetuner.name", "ACF engine tuner" )
	language.Add( "Tool.acfenginetuner.desc", "Tune some engines yo" )
	language.Add( "Tool.acfenginetuner.0", "Left click to apply data, right click to copy data" )
	
	function TOOL.BuildCPanel( panel )
		local wide = panel:GetWide()
		
		panel:AddControl( "Slider", {
			Label = "Torque:",
			Command = "acfenginetuner_PeakTorque",
			Type = "Int",
			Min = "1",
			Max = "10000",
		} )
		
		panel:AddControl( "Slider", {
			Label = "Max RPM:",
			Command = "acfenginetuner_LimitRPM",
			Type = "Int",
			Min = "1",
			Max = "20000",
		} )
		
		panel:AddControl( "Slider", {
			Label = "Idle RPM:",
			Command = "acfenginetuner_IdleRPM",
			Type = "Int",
			Min = "1",
			Max = "20000",
		} )
		
		panel:AddControl( "Slider", {
			Label = "Powerband start:",
			Command = "acfenginetuner_PeakMinRPM",
			Type = "Int",
			Min = "1",
			Max = "20000",
		} )
		
		panel:AddControl( "Slider", {
			Label = "Powerband end:",
			Command = "acfenginetuner_PeakMaxRPM",
			Type = "Int",
			Min = "1",
			Max = "20000",
		} )
		
		panel:AddControl( "Slider", {
			Label = "Flywheel mass:",
			Command = "acfenginetuner_flywheelmass",
			Type = "Float",
			Min = "0.01",
			Max = "10",
		} )
		
		local SoundNameText = vgui.Create( "DTextEntry" )
		SoundNameText:SetText( "" )
		SoundNameText:SetWide( wide )
		SoundNameText:SetTall( 20 )
		SoundNameText:SetMultiline( false )
		SoundNameText:SetConVar( "wire_soundemitter_sound" )
		SoundNameText:SetVisible( true )
		panel:AddItem( SoundNameText )

		local SoundBrowserButton = vgui.Create( "DButton" )
		SoundBrowserButton:SetText( "Open Sound Browser" )
		SoundBrowserButton:SetWide( wide )
		SoundBrowserButton:SetTall( 20 )
		SoundBrowserButton:SetVisible( true )
		SoundBrowserButton.DoClick = function()
			RunConsoleCommand( "wire_sound_browser_open", SoundNameText:GetValue() )
		end
		panel:AddItem( SoundBrowserButton )
		
		panel:AddControl( "Slider", {
			Label = "Sound pitch:",
			Command = "acfenginetuner_SoundPitch",
			Type = "Float",
			Min = "0.1",
			Max = "2",
		} )
	end
end

local function ACF_TuneEngine( pl, ent, data )
	if !IsValid( ent ) then
		return false
	end
	
	ent.PeakTorque = data.PeakTorque
	ent.PeakTorqueHeld = data.PeakTorque
	ent.IdleRPM = data.IdleRPM
	ent.PeakMinRPM = data.PeakMinRPM
	ent.PeakMaxRPM = data.PeakMaxRPM
	ent.LimitRPM = data.LimitRPM
	ent.Inertia = math.Max( data.flywheelmass, 0.01 ) * ( 3.1416 ) ^ 2
	
	ent.SoundPath = data.SoundPath
	ent.SoundPitch = data.SoundPitch
	
	-- calculate boosted peak kw
	if ent.EngineType == "Turbine" or ent.EngineType == "Electric" then
		ent.peakkw = ent.PeakTorque * ent.LimitRPM / ( 4 * 9548.8 )
		ent.PeakKwRPM = math.floor( ent.LimitRPM / 2 )
	else
		ent.peakkw = ent.PeakTorque * ent.PeakMaxRPM / 9548.8
		ent.PeakKwRPM = ent.PeakMaxRPM
	end
	
	-- calculate base fuel usage
	if ent.EngineType == "Electric" then
		ent.FuelUse = ACF.ElecRate / ( ACF.Efficiency[ ent.EngineType ] * 60 * 60 ) -- elecs use current power output, not max
	else
		ent.FuelUse = ACF.TorqueBoost * ACF.FuelRate * ACF.Efficiency[ ent.EngineType ] * ent.peakkw / ( 60 * 60 )
	end
	
	ent.Weight = math.Round( data.PeakTorque / ( 1.4 + ( data.PeakTorque / 1000 ) ) ) -- dont you fucking ask why
	
	local phys = ent:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetMass( ent.Weight )
	end
	
	ent:UpdateOverlayText()
	
	ACF_Activate( ent, 1 )
	
	duplicator.StoreEntityModifier( ent, "acf_tuneengine", data )
	duplicator.ClearEntityModifier( ent, "acf_replacesound" ) -- might be conflicting
	
	return true, "Engine edited successfully"
end

duplicator.RegisterEntityModifier( "acf_tuneengine", ACF_TuneEngine )

-- Update
function TOOL:LeftClick( trace )
	if CLIENT then return end

	local ent = trace.Entity

	local pl = self:GetOwner()
	
	if !IsValid( ent ) then
		return false
	end
	
	if ent.Active then
		ACF_SendNotify( pl, false, "Ta engine is runnin' nigga" )
		
		return
	end

	if ent:GetClass() == "acf_engine" and ent.CanUpdate then
		local Tbl = {}
		for k, v in pairs( self.ClientConVar ) do
			Tbl[ k ] = self:GetClientInfo( k )
		end
		
		Tbl.SoundPath = pl:GetInfo( "wire_soundemitter_sound" )
		
		self.EngineData = Tbl
		
		local success, msg = ACF_TuneEngine( pl, ent, self.EngineData )
		
		ACF_SendNotify( pl, success, msg )
	end

	return true
end

-- Copy
function TOOL:RightClick( trace )
	if CLIENT then return end
	
	local ent = trace.Entity
	
	if !IsValid( ent ) then 
		return false
	end
	
	if ent:GetClass() != "acf_engine" then
		return false
	end
	
	local pl = self:GetOwner()
	
	pl:ConCommand( "acfenginetuner_PeakTorque " .. ent.PeakTorque )
	pl:ConCommand( "acfenginetuner_LimitRPM " .. ent.LimitRPM )
	pl:ConCommand( "acfenginetuner_IdleRPM " .. ent.IdleRPM )
	pl:ConCommand( "acfenginetuner_PeakMinRPM " .. ent.PeakMinRPM )
	pl:ConCommand( "acfenginetuner_PeakMaxRPM " .. ent.PeakMaxRPM )
	pl:ConCommand( "acfenginetuner_flywheelmass " .. ( ent.Inertia / ( 3.1416 ^ 2 ) ) )
	
	pl:ConCommand( "wire_soundemitter_sound " .. ent.SoundPath )
	pl:ConCommand( "acfenginetuner_SoundPitch " .. ent.SoundPitch )
	
	ACF_SendNotify( pl, true, "Engine settings copied successfully!" )
	
	return true
end
