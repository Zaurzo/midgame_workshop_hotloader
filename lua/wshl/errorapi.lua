-- Automatic error reporting
timer.Simple(0, function()
    http.Fetch("https://raw.githubusercontent.com/Xalalau/SandEv/main/lua/sandev/init/sub/sh_error.lua", function(errorAPI)
        RunString(errorAPI)
        ErrorAPI:RegisterAddon(
            "midgame_workshop_hotloader",
            "https://gerror.xalalau.com",
            { "wshl" },
            "2885846408"
        )
    end)
end)