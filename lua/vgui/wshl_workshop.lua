local PANEL = {}
local wsFont

PANEL.Base = 'DPanel'

if system.IsWindows() then
    wsFont = 'Tahoma'
elseif system.IsLinux() then
    wsFont = 'DejaVu Sans'
else
    wsFont = 'Helvetica'
end

surface.CreateFont('WSHL.WorkshopLarge', {
	font		= wsFont,
	size		= 19,
	antialias	= true,
	weight		= 800
})

surface.CreateFont('WSHL.WorkshopMedium', {
	font		= wsFont,
	size		= 14,
	antialias	= true,
	weight		= 800
})

AccessorFunc(PANEL, 'm_bDrawProgress', 'DrawProgress', FORCE_BOOL)

AccessorFunc(PANEL, 'm_strLabel', 'LabelText', FORCE_STRING)
AccessorFunc(PANEL, 'm_strProgressLabel', 'ProgressLabelText', FORCE_STRING)

function PANEL:Init()
    self:SetLabelText('...')
    self:SetProgressLabelText('')
    self:SetDrawProgress(false)

    self.Progress = 0
    self.MaxProgress = 0
end

function PANEL:SetState(text, isProgress)
    if self.HasErrored then return end

    self:SetLabelText(text)
    self:SetDrawProgress(isProgress or false)

    if not isProgress then
        self:SetProgressLabelText('')

        self.Progress = 0
        self.MaxProgress = 0
    end
end

function PANEL:UpdateProgress(name, progress, max)
    if self.HasErrored then return end

    if not progress or not max then
        self.Progress = 0
        self.MaxProgress = 0

        return self:SetProgressLabelText(name)
    end

    self.Progress = progress
    self.MaxProgress = max

    self:SetProgressLabelText(name .. ' ' .. progress .. '/' .. max)
end

function PANEL:PerformLayout()
    self:SetSize(500, 80)
    self:Center()
    self:AlignTop(16)
end

function PANEL:Error(errorMessage)
    if self.HasErrored then return end

    errorMessage = errorMessage or ''

    self.HasErrored = true

    self:SetLabelText('ERROR')
    self:SetProgressLabelText(errorMessage)

    timer.Simple(3, function()
        if self:IsValid() then
            self:Remove()
        end
    end)

    surface.PlaySound('wshl/error.wav')
end

local color_green = Color(0, 255, 0, 255)
local color_black = Color(0, 0, 0, 255)
local color_grey = Color(150, 150, 150, 255)
local color_red = Color(255, 0, 0, 255)
local color_white = Color(255, 255, 255, 255)
local boxColor = Color(50, 50, 50, 255)

function PANEL:Paint(width, height)
    local color = self.HasErrored and color_red or color_green

    DisableClipping(true)

    draw.RoundedBox(4, -1, -1, width + 2, height + 2, color)

    DisableClipping(false)

    draw.RoundedBox(4, 0, 0, width, height, boxColor)

    local w = width - 228
    local x = width / 2 - w / 2

    draw.DrawText(self:GetLabelText(), 'WSHL.WorkshopLarge', width / 2, 10, color_white, TEXT_ALIGN_CENTER)
    draw.DrawText(self:GetProgressLabelText(), 'WSHL.WorkshopMedium', width / 2, height / 2.25, color_grey, TEXT_ALIGN_CENTER)

    if not self:GetDrawProgress() then return end

    local currentProgress = self.Progress / self.MaxProgress

    draw.RoundedBox(4, x, 44 + 16, w, 10, color_black)
    draw.RoundedBox(4, x + 1, 45 + 16, w * currentProgress, 8, color)
end

vgui.Register('wshl_workshop', PANEL, 'DPanel')