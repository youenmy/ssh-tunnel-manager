-- SSH Tunnel Manager — LuCI Controller
module("luci.controller.sshtunnel", package.seeall)

function index()
    entry({"admin", "services", "sshtunnel"}, cbi("sshtunnel"), _("SSH Tunnel"), 90)
end
