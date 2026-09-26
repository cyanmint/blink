/* HermesLink AI-generated glue code; created by cyanmint's coding agent.
 * AI-generated content has no copyright holder and is not subject to copyright. */
#include <Python.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <dlfcn.h>
#include <pthread.h>

static void report_runtime_message(const char *message) {
    typedef void (*append_log_fn)(const char *);
    typedef int (*output_fd_fn)(int);
    append_log_fn append_log = (append_log_fn)dlsym(RTLD_DEFAULT, "HermesLinkAppendLog");
    output_fd_fn output_fd = (output_fd_fn)dlsym(RTLD_DEFAULT, "HermesLinkOutputFD");
    if (append_log != NULL) {
        append_log(message);
    }
    int fd = output_fd == NULL ? STDERR_FILENO : output_fd(1);
    if (fd >= 0) {
        dprintf(fd, "%s\n", message);
    }
}

static int report_python_error(const char *stage) {
    char line[1024];
    snprintf(line, sizeof(line), "hermes: %s failed (error=%d)", stage,
             PyErr_Occurred() != NULL);
    report_runtime_message(line);
    if (PyErr_Occurred()) {
        PyObject *type = NULL;
        PyObject *value = NULL;
        PyObject *traceback = NULL;
        PyErr_Fetch(&type, &value, &traceback);
        PyErr_NormalizeException(&type, &value, &traceback);
        PyObject *text = value == NULL ? NULL : PyObject_Str(value);
        const char *message = text == NULL ? "<unprintable>" : PyUnicode_AsUTF8(text);
        snprintf(line, sizeof(line), "hermes: python error: %s",
                 message == NULL ? "<non-utf8>" : message);
        report_runtime_message(line);
        Py_XDECREF(text);
        Py_XDECREF(type);
        Py_XDECREF(value);
        Py_XDECREF(traceback);
        PyErr_Clear();
    }
    return 1;
}

static int handle_system_exit(void) {
    if (!PyErr_ExceptionMatches(PyExc_SystemExit)) return -1;
    PyObject *type = NULL, *value = NULL, *traceback = NULL;
    PyErr_Fetch(&type, &value, &traceback);
    PyErr_NormalizeException(&type, &value, &traceback);
    PyObject *code = value == NULL ? NULL : PyObject_GetAttrString(value, "code");
    if (code == NULL && PyErr_Occurred()) PyErr_Clear();
    int result = 0;
    if (code != NULL && code != Py_None) {
        if (PyLong_Check(code)) {
            long exit_code = PyLong_AsLong(code);
            result = PyErr_Occurred() ? 1 : (int)exit_code;
            if (PyErr_Occurred()) PyErr_Clear();
        } else {
            PyObject *text = PyObject_Str(code);
            const char *message = text == NULL ? NULL : PyUnicode_AsUTF8(text);
            if (message != NULL) {
                char line[1024];
                snprintf(line, sizeof(line), "%s", message);
                report_runtime_message(line);
            }
            Py_XDECREF(text);
            if (PyErr_Occurred()) PyErr_Clear();
            result = 1;
        }
    }
    Py_XDECREF(code);
    Py_XDECREF(type);
    Py_XDECREF(value);
    Py_XDECREF(traceback);
    PyErr_Clear();
    return result;
}

static int set_command_global(PyObject *globals, const char *name, PyObject *value) {
    if (value == NULL) return -1;
    int result = PyDict_SetItemString(globals, name, value);
    Py_DECREF(value);
    return result;
}

static PyObject *new_python_globals(const char *filename) {
    PyObject *globals = PyDict_New();
    if (globals == NULL) return NULL;
    int failed = PyDict_SetItemString(globals, "__builtins__", PyEval_GetBuiltins()) < 0 ||
        set_command_global(globals, "__name__", PyUnicode_FromString("__main__")) < 0;
    if (!failed && filename != NULL) {
        failed = set_command_global(globals, "__file__",
                                   PyUnicode_DecodeFSDefault(filename)) < 0;
    }
    if (failed) {
        Py_DECREF(globals);
        return NULL;
    }
    return globals;
}

static PyObject *run_python_string(const char *source) {
    PyObject *globals = new_python_globals(NULL);
    if (globals == NULL) return NULL;
    PyObject *result = PyRun_StringFlags(source, Py_file_input, globals, globals, NULL);
    Py_DECREF(globals);
    return result;
}

static int set_webui_argv(int argc, char **argv) {
    PyObject *sys_module = PyImport_ImportModule("sys");
    if (sys_module == NULL) return -1;
    PyObject *new_argv = PyList_New(argc > 1 ? argc - 1 : 1);
    if (new_argv == NULL) {
        Py_DECREF(sys_module);
        return -1;
    }
    PyObject *item = PyUnicode_DecodeFSDefault(argv[0]);
    if (item == NULL) {
        Py_DECREF(new_argv);
        Py_DECREF(sys_module);
        return -1;
    }
    PyList_SET_ITEM(new_argv, 0, item);
    for (int i = 2; i < argc; ++i) {
        item = PyUnicode_DecodeFSDefault(argv[i]);
        if (item == NULL) {
            Py_DECREF(new_argv);
            Py_DECREF(sys_module);
            return -1;
        }
        PyList_SET_ITEM(new_argv, i - 1, item);
    }
    int result = PyObject_SetAttrString(sys_module, "argv", new_argv);
    Py_DECREF(new_argv);
    Py_DECREF(sys_module);
    return result;
}

static void flush_python_stdio(void) {
    PyObject *sys_module = PyImport_ImportModule("sys");
    if (sys_module != NULL) {
        const char *streams[] = {"stdout", "stderr"};
        for (size_t i = 0; i < sizeof(streams) / sizeof(streams[0]); ++i) {
            PyObject *stream = PyObject_GetAttrString(sys_module, streams[i]);
            PyObject *flushed = stream == NULL
                ? NULL : PyObject_CallMethod(stream, "flush", NULL);
            if (flushed == NULL) PyErr_Clear();
            Py_XDECREF(flushed);
            Py_XDECREF(stream);
        }
        Py_DECREF(sys_module);
    }
    if (PyErr_Occurred()) PyErr_Clear();
    fflush(stdout);
    fflush(stderr);
}

int hermes_register_native_modules(void);

static const char *runtime_suffixes[] = {
    "", "/python", "/hermes", "/hermes-webui", "/python/site-packages"
};
static pthread_once_t native_modules_once = PTHREAD_ONCE_INIT;
static int native_modules_result = -1;
static int runtime_uses_existing_interpreter;
static int runtime_paths_installed;

static void register_native_modules_once(void) {
    if (Py_IsInitialized()) {
        /* A-Shell or another host component initialized the shared CPython
         * runtime first. AppendInittab is fatal after that point; adopt the
         * existing main interpreter instead of attempting late registration. */
        runtime_uses_existing_interpreter = 1;
        native_modules_result = 0;
        report_runtime_message("hermes: adopting existing CPython runtime; skipping inittab registration");
        return;
    }
    native_modules_result = hermes_register_native_modules();
    if (native_modules_result == 0) {
        report_runtime_message("hermes: native Python modules registered");
    } else {
        report_runtime_message("hermes: native Python module registration failed");
    }
}

__attribute__((visibility("default")))
int hermes_runtime_prepare(void) {
    pthread_once(&native_modules_once, register_native_modules_once);
    return native_modules_result;
}

static int append_existing_runtime_paths(void) {
    const char *runtime_root = getenv("HERMES_RUNTIME_ROOT");
    char runtime_path[PATH_MAX];
    if (runtime_root == NULL || runtime_root[0] == '\0') runtime_root = ".";
    if (snprintf(runtime_path, sizeof(runtime_path), "%s/hermesrt.zip", runtime_root)
            >= (int)sizeof(runtime_path)) {
        report_runtime_message("hermes: runtime path is too long");
        return -1;
    }

    PyObject *sys_path = PySys_GetObject("path");
    if (sys_path == NULL || !PyList_Check(sys_path)) {
        PyErr_SetString(PyExc_RuntimeError, "existing Python runtime has no sys.path list");
        return -1;
    }
    for (size_t i = 0; i < sizeof(runtime_suffixes) / sizeof(runtime_suffixes[0]); ++i) {
        char path[PATH_MAX];
        if (snprintf(path, sizeof(path), "%s%s", runtime_path, runtime_suffixes[i])
                >= (int)sizeof(path)) {
            PyErr_SetString(PyExc_RuntimeError, "runtime search path is too long");
            return -1;
        }
        PyObject *entry = PyUnicode_DecodeFSDefault(path);
        if (entry == NULL) return -1;
        int present = PySequence_Contains(sys_path, entry);
        if (present == 0 && PyList_Append(sys_path, entry) != 0) {
            Py_DECREF(entry);
            return -1;
        }
        Py_DECREF(entry);
        if (present < 0) return -1;
    }
    runtime_paths_installed = 1;
    return 0;
}

/* Keep CPython initialized for the app lifetime and run every command in the
 * main interpreter.  The iOS build contains legacy static extensions, and
 * CPython's PyGILState API is only supported with the main interpreter. */
static pthread_once_t runtime_init_once = PTHREAD_ONCE_INIT;
static int runtime_init_result = 70;

static void initialize_runtime_once(void) {
    if (hermes_runtime_prepare() != 0) return;
    setenv("HERMES_IOS_TERMINAL", "1", 1);

    if (Py_IsInitialized()) {
        runtime_uses_existing_interpreter = 1;
        runtime_init_result = 0;
        report_runtime_message("hermes: reusing initialized CPython runtime");
        return;
    }

    const char *runtime_root = getenv("HERMES_RUNTIME_ROOT");
    char runtime_path[PATH_MAX];
    if (runtime_root == NULL || runtime_root[0] == '\0') runtime_root = ".";
    if (snprintf(runtime_path, sizeof(runtime_path), "%s/hermesrt.zip", runtime_root)
            >= (int)sizeof(runtime_path)) {
        report_runtime_message("hermes: runtime path is too long");
        return;
    }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.parse_argv = 0;
    config.use_system_logger = 0;
    /* ios_system owns signal routing and its command-specific terminal streams. */
    config.install_signal_handlers = 0;
    config.configure_c_stdio = 0;
    config.buffered_stdio = 0;
    config.site_import = 0;

    PyStatus status = PyConfig_SetString(&config, &config.program_name, L"./hermes");
    if (PyStatus_Exception(status)) {
        report_runtime_message(status.err_msg == NULL ? "hermes: Python config failed" : status.err_msg);
        PyConfig_Clear(&config);
        return;
    }

    // The a-Shell iOS getpath port reads Py_GetArgcArgv()[0] without checking
    // for an empty vector; embedded startup must seed an argv before init.
    wchar_t *runtime_argv[] = {L"./hermes"};
    status = PyConfig_SetArgv(&config, 1, runtime_argv);
    if (PyStatus_Exception(status)) {
        report_runtime_message(status.err_msg == NULL
            ? "hermes: Python argv configuration failed" : status.err_msg);
        PyConfig_Clear(&config);
        return;
    }

    for (size_t i = 0; i < sizeof(runtime_suffixes) / sizeof(runtime_suffixes[0]); ++i) {
        char path[PATH_MAX];
        if (snprintf(path, sizeof(path), "%s%s", runtime_path,
                     runtime_suffixes[i]) >= (int)sizeof(path)) {
            report_runtime_message("hermes: runtime path is too long");
            PyConfig_Clear(&config);
            return;
        }
        wchar_t *wide_path = Py_DecodeLocale(path, NULL);
        if (wide_path == NULL) {
            report_runtime_message("hermes: unable to decode runtime path");
            PyConfig_Clear(&config);
            return;
        }
        status = PyWideStringList_Append(&config.module_search_paths, wide_path);
        PyMem_RawFree(wide_path);
        if (PyStatus_Exception(status)) {
            report_runtime_message(status.err_msg == NULL ? "hermes: Python config failed" : status.err_msg);
            PyConfig_Clear(&config);
            return;
        }
    }
    config.module_search_paths_set = 1;

    report_runtime_message("hermes: initializing embedded CPython");
    status = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(status)) {
        report_runtime_message(status.err_msg == NULL ? "hermes: Python initialization failed" : status.err_msg);
        PyConfig_Clear(&config);
        return;
    }

    PyConfig_Clear(&config);
    report_runtime_message("hermes: releasing initialization thread state");
    PyEval_SaveThread();
    runtime_init_result = 0;
    report_runtime_message("hermes: embedded CPython initialized");
}

__attribute__((visibility("default")))
int hermes_runtime_initialize(void) {
    if (!pthread_main_np()) {
        report_runtime_message("hermes: CPython initialization must run on the main thread");
        return 70;
    }
    pthread_once(&runtime_init_once, initialize_runtime_once);
    return runtime_init_result;
}

static int set_command_argv(int argc, char **argv) {
    wchar_t **wide_argv = PyMem_RawCalloc((size_t)argc + 1, sizeof(*wide_argv));
    if (wide_argv == NULL) {
        report_runtime_message("hermes: unable to allocate argument vector");
        return 70;
    }
    int result = 0;
    for (int i = 0; i < argc; ++i) {
        wide_argv[i] = Py_DecodeLocale(argv[i], NULL);
        if (wide_argv[i] == NULL) {
            report_runtime_message("hermes: unable to decode command argument");
            result = 70;
            break;
        }
    }
    if (result == 0) PySys_SetArgvEx(argc, wide_argv, 0);
    for (int i = 0; i < argc; ++i) PyMem_RawFree(wide_argv[i]);
    PyMem_RawFree(wide_argv);
    return result;
}

static int run_python_command(int argc, char **argv) {
    PyObject *result = NULL;
    if (argc > 1 && strcmp(argv[1], "-c") == 0 && argc > 2) {
        result = run_python_string(argv[2]);
    } else if (argc > 1 && argv[1][0] != '-') {
        FILE *script = fopen(argv[1], "r");
        if (script == NULL) {
            report_runtime_message("python: unable to open script");
            return 2;
        }
        PyObject *globals = new_python_globals(argv[1]);
        result = globals == NULL ? NULL
            : PyRun_FileExFlags(script, argv[1], Py_file_input,
                                globals, globals, 1, NULL);
        if (globals == NULL) fclose(script);
        Py_XDECREF(globals);
    } else {
        result = run_python_string(
            "import code; code.interact(local=dict(globals(), **locals()))");
    }
    if (result == NULL) {
        int system_exit = handle_system_exit();
        if (system_exit >= 0) return system_exit;
        return report_python_error("run python");
    }
    Py_DECREF(result);
    return 0;
}

static int run_hermes_command(int argc, char **argv) {
    const char *entry_module = (argc > 1 && strcmp(argv[1], "webui") == 0)
        ? "server" : (argc > 1 && strcmp(argv[1], "upgrade") == 0)
            ? "hermes_cli.upgrade" : "hermes_cli.main";
    if (argc > 1 && (strcmp(argv[1], "webui") == 0 || strcmp(argv[1], "upgrade") == 0)) {
        if (set_webui_argv(argc, argv) != 0) {
            return report_python_error("set command arguments");
        }
    }
    PyObject *module = PyImport_ImportModule(entry_module);
    if (module == NULL) {
        int system_exit = handle_system_exit();
        if (system_exit >= 0) return system_exit;
        return report_python_error("import entry module");
    }
    PyObject *entrypoint = PyObject_GetAttrString(module, "main");
    Py_DECREF(module);
    if (entrypoint == NULL || !PyCallable_Check(entrypoint)) {
        Py_XDECREF(entrypoint);
        return report_python_error("find entrypoint main");
    }
    PyObject *return_value = PyObject_CallNoArgs(entrypoint);
    Py_DECREF(entrypoint);
    if (return_value == NULL) {
        int system_exit = handle_system_exit();
        if (system_exit >= 0) return system_exit;
        return report_python_error("run entrypoint main");
    }
    int result = PyLong_Check(return_value) ? (int)PyLong_AsLong(return_value) : 0;
    Py_DECREF(return_value);
    return result;
}

static int hermes_runtime_main_impl(int argc, char **argv, int python_mode) {
    report_runtime_message("hermes: runtime command entered");
    if (hermes_runtime_initialize() != 0) return runtime_init_result;

    /* All commands use the main interpreter: it is the only configuration
     * supported by PyGILState_Ensure and by the linked legacy extensions. */
    report_runtime_message("hermes: acquiring CPython thread state");
    PyGILState_STATE gil_state = PyGILState_Ensure();
    report_runtime_message("hermes: CPython thread state acquired");
    if (runtime_uses_existing_interpreter && !runtime_paths_installed &&
            append_existing_runtime_paths() != 0) {
        int path_error = report_python_error("configure existing runtime paths");
        PyGILState_Release(gil_state);
        return path_error;
    }
    PyObject *old_argv = PySys_GetObject("argv");
    PyObject *saved_argv = old_argv == NULL ? NULL : PySequence_List(old_argv);
    if (saved_argv == NULL) {
        PyErr_Clear();
        PyGILState_Release(gil_state);
        report_runtime_message("hermes: unable to preserve command arguments");
        return 70;
    }
    report_runtime_message("hermes: installing command arguments");
    int result = set_command_argv(argc, argv);
    if (result == 0) {
        report_runtime_message("hermes: importing sitecustomize");
        PyObject *bootstrap = PyImport_ImportModule("sitecustomize");
        if (bootstrap == NULL) {
            result = report_python_error("import sitecustomize");
        } else {
            Py_DECREF(bootstrap);
            report_runtime_message(python_mode
                ? "hermes: dispatching Python command"
                : "hermes: dispatching Hermes command");
            result = python_mode ? run_python_command(argc, argv)
                                 : run_hermes_command(argc, argv);
        }
    }
    flush_python_stdio();
    if (PySys_SetObject("argv", saved_argv) != 0) PyErr_Clear();
    Py_DECREF(saved_argv);
    PyGILState_Release(gil_state);
    report_runtime_message("hermes: runtime command returned");
    return result;
}

__attribute__((visibility("default")))
int hermes_runtime_main(int argc, char **argv) {
    return hermes_runtime_main_impl(argc, argv, 0);
}

__attribute__((visibility("default")))
int hermes_python_main(int argc, char **argv) {
    return hermes_runtime_main_impl(argc, argv, 1);
}
