' ********************************************************************
' * StreamingTV: Registry Storage Helper (roRegistrySection)
' * Securely manages BYOP credentials, pairing tokens, and app state
' ********************************************************************

function GetAuthRegistry() as Object
    return CreateObject("roRegistrySection", "StreamingTV_Auth")
end function

function GetPrefRegistry() as Object
    return CreateObject("roRegistrySection", "StreamingTV_Prefs")
end function

function Storage_GetAuth(key as String, defaultVal = "" as Dynamic) as Dynamic
    sec = GetAuthRegistry()
    if sec.Exists(key)
        return sec.Read(key)
    end if
    return defaultVal
end function

function Storage_SetAuth(key as String, val as String) as Boolean
    sec = GetAuthRegistry()
    sec.Write(key, val)
    return sec.Flush()
end function

function Storage_DeleteAuth(key as String) as Boolean
    sec = GetAuthRegistry()
    sec.Delete(key)
    return sec.Flush()
end function

function Storage_ClearAllAuth() as Boolean
    sec = GetAuthRegistry()
    for each k in sec.GetKeyList()
        sec.Delete(k)
    end for
    return sec.Flush()
end function

function Storage_GetPref(key as String, defaultVal = "" as Dynamic) as Dynamic
    sec = GetPrefRegistry()
    if sec.Exists(key)
        return sec.Read(key)
    end if
    return defaultVal
end function

function Storage_SetPref(key as String, val as String) as Boolean
    sec = GetPrefRegistry()
    sec.Write(key, val)
    return sec.Flush()
end function
