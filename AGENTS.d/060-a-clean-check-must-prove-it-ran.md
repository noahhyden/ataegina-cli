## A clean check must prove it ran

check_agents_rule_length and check_one_line_comments both refuse to pass when nothing matched, rather than reporting success over an empty set, because a guard that silently scanned zero files is indistinguishable from one that passed.
