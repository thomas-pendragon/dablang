#include "cvm.h"

void BaseDabVM::define_default_classes()
{
    DabClass string_class;
    string_class.index    = CLASS_STRING;
    string_class.name     = "String";
    string_class.builtin  = true;
    classes[CLASS_STRING] = string_class;

    DabClass fixnum_class;
    fixnum_class.index    = CLASS_FIXNUM;
    fixnum_class.name     = "Fixnum";
    fixnum_class.builtin  = true;
    classes[CLASS_FIXNUM] = fixnum_class;

    DabClass boolean_class;
    boolean_class.index    = CLASS_BOOLEAN;
    boolean_class.name     = "Boolean";
    boolean_class.builtin  = true;
    classes[CLASS_BOOLEAN] = boolean_class;
}
