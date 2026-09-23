/* HermesLink AI-generated glue code; created by cyanmint's coding agent.
 * AI-generated content has no copyright holder and is not subject to copyright.
 *
 * This module bridges Python's local shell calls to the host ios_system command
 * interpreter used by Blink/a-Shell. It does not implement shell commands.
 */
#include <Python.h>
#include <errno.h>

#if defined(__GNUC__)
extern int ios_system(const char *inputCmd) __attribute__((weak_import));
extern int ios_executable(const char *cmd) __attribute__((weak_import));
#else
extern int ios_system(const char *inputCmd);
extern int ios_executable(const char *cmd);
#endif

static PyObject *hermeslink_system(PyObject *self, PyObject *args) {
    const char *command;
    (void)self;
    if (!PyArg_ParseTuple(args, "s:system", &command)) {
        return NULL;
    }
    if (ios_system == NULL) {
        PyErr_SetString(PyExc_OSError, "ios_system is unavailable in this host");
        return NULL;
    }
    return PyLong_FromLong((long)ios_system(command));
}

static PyObject *hermeslink_executable(PyObject *self, PyObject *args) {
    const char *command;
    (void)self;
    if (!PyArg_ParseTuple(args, "s:executable", &command)) {
        return NULL;
    }
    if (ios_executable == NULL) {
        Py_RETURN_FALSE;
    }
    return PyBool_FromLong(ios_executable(command) != 0);
}

static PyMethodDef methods[] = {
    {"system", hermeslink_system, METH_VARARGS, "Run a command through ios_system."},
    {"executable", hermeslink_executable, METH_VARARGS, "Check a command in ios_system."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "_hermeslink_shell",
    "HermesLink bridge to the Blink/a-Shell command interpreter.",
    -1,
    methods,
};

PyMODINIT_FUNC PyInit__hermeslink_shell(void) {
    return PyModule_Create(&module);
}
