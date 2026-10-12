' ********************************************************************
' * ApiTask: off-render-thread HTTP. Every network call in this app
' * must run here -- never in a SceneGraph component's init()/event
' * handlers. Roku certification and UI responsiveness both require it.
' ********************************************************************

sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    action = m.top.action
    args = m.top.args
    if args = invalid then args = {}
    ctx = m.top.context

    resp = {
        context: ctx,
        action: action,
        success: false,
        data: invalid,
        error: "Unknown action"
    }

    if action = "device_request_code"
        data = Device_RequestCode(args.apiBase, args.macAddress, args.deviceUuid)
        resp.data = data
        if data <> invalid and data.success
            resp.success = true
            resp.error = ""
        else
            resp.error = "Could not reach pairing service."
        end if

    else if action = "device_poll_status"
        data = Device_PollStatus(args.apiBase, args.code, args.macAddress)
        resp.data = data
        if data <> invalid
            resp.success = true
            resp.error = ""
        else
            resp.error = "Could not reach pairing service."
        end if

    else if action = "device_get_config"
        data = Device_GetConfig(args.apiBase, args.token)
        resp.data = data
        resp.success = true
        resp.error = ""

    else if action = "device_request_edit_code"
        data = Device_RequestEditCode(args.apiBase, args.token, args.macAddress)
        resp.data = data
        if data <> invalid and data.success
            resp.success = true
            resp.error = ""
        else
            resp.error = "Could not create edit code."
        end if

    else if action = "device_get_playlists"
        data = Device_GetPlaylists(args.apiBase, args.token)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load playlists."

    else if action = "xc_login"
        data = XC_Login(args.serverUrl, args.username, args.password)
        resp.data = data
        if data <> invalid and data.success
            resp.success = true
            resp.error = ""
        else
            if data <> invalid and data.errorMessage <> "" then resp.error = data.errorMessage
        end if

    else if action = "get_live_categories"
        data = XC_GetLiveCategories(args.serverUrl, args.username, args.password)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load categories."

    else if action = "get_live_streams"
        data = XC_GetLiveStreams(args.serverUrl, args.username, args.password, args.categoryId)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load channels."

    else if action = "get_short_epg"
        data = XC_GetShortEpg(args.serverUrl, args.username, args.password, args.streamId)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load guide."

    else if action = "get_vod_categories"
        data = XC_GetVodCategories(args.serverUrl, args.username, args.password)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load categories."

    else if action = "get_vod_streams"
        data = XC_GetVodStreams(args.serverUrl, args.username, args.password, args.categoryId)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load titles."

    else if action = "get_series_categories"
        data = XC_GetSeriesCategories(args.serverUrl, args.username, args.password)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load categories."

    else if action = "get_series"
        data = XC_GetSeries(args.serverUrl, args.username, args.password, args.categoryId)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load series."

    else if action = "get_series_info"
        data = XC_GetSeriesInfo(args.serverUrl, args.username, args.password, args.seriesId)
        resp.data = data
        resp.success = data <> invalid
        if not resp.success then resp.error = "Could not load episodes."

    else if action = "player_bind"
        data = Player_Bind(args.apiBase, args.mac, args.pin)
        resp.data = data
        resp.success = data.success
        if not resp.success then resp.error = data.error

    else if action = "player_fetch_payload"
        data = Player_FetchPayload(args.apiBase, args.mac, args.pin)
        resp.data = data
        resp.success = data.success
        if not resp.success then resp.error = data.error

    else if action = "player_unbind"
        data = Player_Unbind(args.apiBase, args.mac, args.pin)
        resp.data = data
        resp.success = data.success

    else if action = "device_logout"
        data = Device_Logout(args.apiBase, args.token)
        resp.data = data
        resp.success = data.success

    else
        resp.error = "Unhandled action: " + action
    end if

    m.top.response = resp
end sub
