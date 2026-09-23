/* HermesLink AI-generated glue code; created by cyanmint's coding agent.
 * AI-generated content has no copyright holder and is not subject to copyright.
 *
 * This module bridges Python's local shell calls to the host ios_system command
 * interpreter used by Blink/a-Shell. It does not implement shell commands.
 */
#include <Python.h>
#include <dlfcn.h>

typedef int (*hermeslink_shell_fn)(const char *);

static hermeslink_shell_fn hermeslink_symbol(const char *name) {
    return (hermeslink_shell_fn)dlsym(RTLD_DEFAULT, name);
}

static PyObject *hermeslink_system(PyObject *self, PyObject *args) {
    const char *command;
    (void)self;
    if (!PyArg_ParseTuple(args, "s:system", &command)) {
        return NULL;
    }
    hermeslink_shell_fn function = hermeslink_symbol("ios_system");
    if (function == NULL) {
        PyErr_SetString(PyExc_OSError, "ios_system is unavailable in this host");
        return NULL;
    }
    return PyLong_FromLong((long)function(command));
}

static PyObject *hermeslink_executable(PyObject *self, PyObject *args) {
    const char *command;
    (void)self;
    if (!PyArg_ParseTuple(args, "s:executable", &command)) {
        return NULL;
    }
    hermeslink_shell_fn function = hermeslink_symbol("ios_executable");
    if (function == NULL) {
        Py_RETURN_FALSE;
    }
    return PyBool_FromLong(function(command) != 0);
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
