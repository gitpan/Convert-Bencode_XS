#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* this is a trimmed down version of Perl_sv_cmp which doesn't consider
 * locale and UTF8: i hope this to be  more compliant with Bencode specs  */
int _raw_cmp(const void *v1, const void *v2) {
    STRLEN cur1, cur2;
    char *pv1, *pv2;
    int cmp, retval;
        
    pv1 = SvPV(*(SV **)v1, cur1);
    pv2 = SvPV(*(SV **)v2, cur2); 
    
    retval = memcmp((void*)pv1, (void*)pv2, cur1 < cur2 ? cur1 : cur2);
    if (retval) {
        cmp = retval < 0 ? -1 : 1;
    } else if (cur1 == cur2) {
        cmp = 0;
    } else {
        cmp = cur1 < cur2 ? -1 : 1;
    }

    return cmp;
}


bool _is_int(char *pv, STRLEN len, STRLEN *offset) {
    STRLEN i = 0;
    bool is_int = 0;
    bool first_zero = 0;
    bool plus = 0;
    bool minus = 0;
    if (pv[0] == '+') i = plus = 1;
    if (pv[0] == '-') i = minus = 1;
        
    for (;i < len;i++) {
        if (isDIGIT(pv[i])) {
            if (!is_int && pv[i] == '0') {
                if (first_zero) {
                    first_zero = 0;
                    break;
                } else {
                    first_zero = 1;
                    continue;
                }
            }
            is_int = 1;
        } else {
            return 0;
        }
    }
    if (is_int ^ first_zero) {
        *offset = (plus || (minus && first_zero)) ? 1 : 0;
        return 1;
    } else {
        return 0;
    }
}



void _bencode(SV *line, SV *stuff, bool coerce, bool hkey) {
    char *pv;
    STRLEN len, offset;
    bool is_int = 0;
    
    if (hkey) {
        pv = SvPV(stuff, len);
        sv_catpvf(line, "%d:%s", len, pv);
        return;
    }
    if (SvIOK(stuff) && !SvNOK(stuff) && !SvPOK(stuff)) {
        sv_catpvf(line, "i%de", SvIVX(stuff));
        return;
    }
    if (SvROK(stuff)) {
        switch (SvTYPE(SvRV(stuff))) {
            AV *av, *keys;
            HV *hv;
            SV *sv; 
            HE *entry; 
            I32 len, i;
            case SVt_PVAV:
                sv_catpv(line, "l");
                av = (AV*)SvRV(stuff);
                len = av_len(av) + 1;
                for (i = 0; i < len; i++) {
                    _bencode(line, *av_fetch(av, i, 0), coerce, 0);
                }
                sv_catpv(line, "e");
                break;
            case SVt_PVHV:
                sv_catpv(line, "d");
                hv = (HV*)SvRV(stuff);
                keys = (AV*)sv_2mortal((SV*)newAV());
                (void)hv_iterinit(hv);
                while (entry = hv_iternext(hv)) {
                    sv = hv_iterkeysv(entry);
                    (void)SvREFCNT_inc(sv);
                    av_push(keys, sv);
                }
                qsort(AvARRAY(keys), av_len(keys) + 1, sizeof(SV*), _raw_cmp);
                len = av_len(keys) + 1;
                for (i = 0; i < len; i++) {
                    sv = *av_fetch(keys, i, 0);
                    _bencode(line, sv, coerce, 1);
                    _bencode(line, HeVAL(
                        hv_fetch_ent(hv, sv, FALSE, 0)
                     ), coerce, 0); 
                }
                sv_catpv(line, "e");
                break;
            default:
                croak("Cannot serialize this kind of reference: %_", stuff);
        }
        return;
    }
    pv = SvPV(stuff, len);
    if (coerce && _is_int(pv, len, &offset)) {
        sv_catpvf(line, "i%se", pv + offset);
    } else {
        sv_catpvf(line, "%d:%s", len, pv);
    }
}


MODULE = Convert::Bencode_XS		PACKAGE = Convert::Bencode_XS		

SV*
bencode(stuff)
    SV * stuff
    PROTOTYPE: $
    PREINIT:
        SV *line = newSV(8100);
    CODE:
        sv_setpv(line, "");
        _bencode(
            line, 
            stuff, 
            SvTRUE(get_sv("Convert::Bencode_XS::COERCE", TRUE)), 
            0
        );
        RETVAL = line;
    OUTPUT:
        RETVAL

void
cleanse(sv)
    SV * sv
    PROTOTYPE: $
    CODE:
        if (SvIOK(sv) && !SvNOK(sv) && !SvPOK(sv)) return;
        (void)SvIV(sv);
        SvIOK_only(sv);


