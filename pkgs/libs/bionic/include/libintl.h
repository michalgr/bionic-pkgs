#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#define gettext(Msgid) ((char *)(Msgid))
#define dgettext(Domainname, Msgid) ((char *)(Msgid))
#define dcgettext(Domainname, Msgid, Category) ((char *)(Msgid))
#define ngettext(Singular, Plural, N) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define dngettext(Domainname, Singular, Plural, N) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define dcngettext(Domainname, Singular, Plural, N, Category) ((char *)((N) == 1 ? (Singular) : (Plural)))
#define textdomain(Domainname) ((char *)(Domainname))
#define bindtextdomain(Domainname, Dirname) ((char *)(Dirname))
#define bind_textdomain_codeset(Domainname, Codeset) ((char *)(Codeset))

#ifdef __cplusplus
}
#endif
