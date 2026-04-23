// Este archivo es necesario porque el esp-idf incluye stdint.h en los headers de *_reg.h , lo cual hace que no se puedan compilar, pero no es necesario para obtener las definiciones que nosotros usamos
// Deberia estar fixed en futura release (6.0.algo)
#ifndef STDINT_WRAPPER_H
#define STDINT_WRAPPER_H

#define _STDINT_H
#define _MACHINE__DEFAULT_TYPES_H

#endif // STDINT_WRAPPER_H
