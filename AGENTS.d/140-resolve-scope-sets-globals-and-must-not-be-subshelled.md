## resolve_scope sets globals and must not be run in a subshell

resolve_scope returns its value via RESOLVED_SCOPE, RESOLVED_SCOPE_SOURCE and RESOLVED_SCOPE_BASE; call it plainly, never inside $(...), or the globals vanish and the F5 none->both nudge and doctor annotation silently break.
