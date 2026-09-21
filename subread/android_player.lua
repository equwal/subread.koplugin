--[[--
Bridge to the audio player on Android, through SubRead Overlay.

KOReader has no notification access, so it cannot see the media session of
the player. SubRead Overlay (space.subread.overlay) has that access and
gives the state of the player to other apps with a content provider. This
module calls that provider over JNI, with the helpers of the KOReader
launcher (android.lua). It must only be loaded on Android.

Each function returns nil when the provider cannot be reached: SubRead
Overlay is not installed, or the call threw a Java exception.
--]]--

local android = require("android")
local ffi = require("ffi")
local logger = require("logger")

local AndroidPlayer = {}

-- The content provider of SubRead Overlay. See its PlayerProvider.
AndroidPlayer.URI = "content://space.subread.overlay.player/state"
-- Name of the app that the user must install.
AndroidPlayer.PACKAGE = "space.subread.overlay"

local NULL = ffi.cast("void *", nil)

--- Clears a pending Java exception. Returns true when there was one.
-- A pending exception makes the next JNI call abort the process, so each
-- call that can throw is followed by this check.
local function clearException(jni, what)
    local env = jni.env
    if env[0].ExceptionCheck(env) == ffi.C.JNI_TRUE then
        env[0].ExceptionClear(env)
        logger.warn("SubRead: Java exception in", what)
        return true
    end
    return false
end

--- Runs fn(jni, resolver, uri) with the ContentResolver of the activity
--- and the Uri of the provider. Frees the local references after.
local function withResolver(fn)
    return android.jni:context(android.app.activity.vm, function(jni)
        local env = jni.env
        local resolver = jni:callObjectMethod(android.app.activity.clazz,
            "getContentResolver", "()Landroid/content/ContentResolver;")
        local uri_text = env[0].NewStringUTF(env, AndroidPlayer.URI)
        local uri = jni:callStaticObjectMethod("android/net/Uri", "parse",
            "(Ljava/lang/String;)Landroid/net/Uri;", uri_text)
        local result = fn(jni, resolver, uri)
        env[0].DeleteLocalRef(env, uri)
        env[0].DeleteLocalRef(env, uri_text)
        env[0].DeleteLocalRef(env, resolver)
        return result
    end)
end

--- Reads the state line of the player. Returns nil when there is no provider.
function AndroidPlayer.query()
    local ok, line = pcall(withResolver, function(jni, resolver, uri)
        local env = jni.env
        -- ContentResolver.query(Uri, String[], String, String[], String).
        -- It returns null when no app has the provider.
        local cursor = jni:callObjectMethod(resolver, "query",
            "(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;",
            uri, NULL, NULL, NULL, NULL)
        if clearException(jni, "query") or cursor == nil then return nil end
        local line
        if jni:callBooleanMethod(cursor, "moveToFirst", "()Z") then
            local text = jni:callObjectMethod(cursor, "getString",
                "(I)Ljava/lang/String;", ffi.new("int32_t", 0))
            if text ~= nil then
                line = jni:to_string(text)
                env[0].DeleteLocalRef(env, text)
            end
        end
        jni:callVoidMethod(cursor, "close", "()V")
        env[0].DeleteLocalRef(env, cursor)
        return line
    end)
    if not ok then
        logger.warn("SubRead: player query failed:", line)
        return nil
    end
    return line
end

--- Sends a command to the player: "play", "pause", or "seek" with the
--- position in milliseconds as a string. Returns true when the provider
--- took the call.
function AndroidPlayer.call(method, argument)
    local ok, done = pcall(withResolver, function(jni, resolver, uri)
        local env = jni.env
        local method_text = env[0].NewStringUTF(env, method)
        local argument_text = argument and env[0].NewStringUTF(env, tostring(argument)) or NULL
        -- ContentResolver.call(Uri, String, String, Bundle). It throws when
        -- no app has the provider.
        local bundle = jni:callObjectMethod(resolver, "call",
            "(Landroid/net/Uri;Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;",
            uri, method_text, argument_text, NULL)
        local failed = clearException(jni, "call " .. method)
        if bundle ~= nil then env[0].DeleteLocalRef(env, bundle) end
        if argument_text ~= NULL then env[0].DeleteLocalRef(env, argument_text) end
        env[0].DeleteLocalRef(env, method_text)
        return not failed
    end)
    if not ok then
        logger.warn("SubRead: player call failed:", done)
        return false
    end
    return done
end

return AndroidPlayer
