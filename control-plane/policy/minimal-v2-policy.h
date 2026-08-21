#pragma once

#include "lxinitshared.h"

namespace wsl::linux::minimal_policy
{
constexpr bool IsMiniInitRequestAllowed(LX_MESSAGE_TYPE Type)
{
    switch (Type)
    {
    case LxMiniInitMessageEarlyConfig:
    case LxMiniInitMessageInitialConfig:
    case LxMiniInitMessageLaunchInit:
        return true;
    default:
        return false;
    }
}

constexpr bool IsDistroControlRequestAllowed(LX_MESSAGE_TYPE Type)
{
    switch (Type)
    {
    case LxInitMessageCreateSession:
    case LxInitMessageInitialize:
    case LxInitMessageTerminateInstance:
    case LxInitCreateProcess:
        return true;
    default:
        return false;
    }
}

constexpr bool IsSessionRequestAllowed(LX_MESSAGE_TYPE Type)
{
    return Type == LxInitMessageCreateProcessUtilityVm;
}

constexpr bool AreDirectProcessFlagsAllowed(int Flags)
{
    constexpr auto ConsoleFlags = LxInitCreateProcessFlagsStdInConsole | LxInitCreateProcessFlagsStdOutConsole |
                                  LxInitCreateProcessFlagsStdErrConsole;
    return Flags >= 0 && (Flags & ~ConsoleFlags) == 0;
}
} // namespace wsl::linux::minimal_policy
