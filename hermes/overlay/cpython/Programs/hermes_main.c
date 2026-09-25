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

static PyObject *run_python_string(const char *source) {
    PyObject *main_module = PyImport_AddModule("__main__");
    if (main_module == NULL) return NULL;
    PyObject *globals = PyModule_GetDict(main_module);
    return PyRun_StringFlags(source, Py_file_input, globals, globals, NULL);
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

/* Keep CPython initialized for the app lifetime.  Each command gets a
 * sub-interpreter: it has its own sys.modules, sys.argv, and __main__, while
 * the shared GIL keeps the legacy statically-linked iOS extensions safe. */
static pthread_once_t runtime_init_once = PTHREAD_ONCE_INIT;
static PyInterpreterState *runtime_main_interpreter;
static int runtime_init_result = 70;

static void initialize_runtime_once(void) {
    setenv("HERMES_IOS_TERMINAL", "1", 1);
    hermes_register_native_modules();

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
    config.buffered_stdio = 0;
    config.site_import = 0;

    PyStatus status = PyConfig_SetString(&config, &config.program_name, L"./hermes");
    if (PyStatus_Exception(status)) {
        report_runtime_message(status.err_msg == NULL ? "hermes: Python config failed" : status.err_msg);
        PyConfig_Clear(&config);
        return;
    }

    const char *runtime_suffixes[] = {
        "", "/python", "/hermes", "/hermes-webui", "/python/site-packages"
    };
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

    status = Py_InitializeFromConfig(&config);
    if (PyStatus_Exception(status)) {
        report_runtime_message(status.err_msg == NULL ? "hermes: Python initialization failed" : status.err_msg);
        PyConfig_Clear(&config);
        return;
    }

    runtime_main_interpreter = PyThreadState_GetInterpreter(PyThreadState_Get());
    PyConfig_Clear(&config);
    PyEval_SaveThread();
    runtime_init_result = 0;
}

static PyThreadState *begin_command_interpreter(PyThreadState **parent_state_out,
                                                int *owns_parent_state_out) {
    /* ios_system can re-enter on a thread that already owns a Python state.
     * Reuse that attached parent; when called with no attached state (for
     * example, from os.system while CPython released the GIL), attach a
     * temporary main-interpreter state for this command to restore later. */
    PyThreadState *parent_state = PyThreadState_GetUnchecked();
    int owns_parent_state = 0;
    if (parent_state == NULL) {
        parent_state = PyThreadState_New(runtime_main_interpreter);
        if (parent_state == NULL) {
            return NULL;
        }
        PyEval_AcquireThread(parent_state);
        owns_parent_state = 1;
    }

    const PyInterpreterConfig command_config = {
        .use_main_obmalloc = 1,
        .allow_fork = 1,
        .allow_exec = 1,
        .allow_threads = 1,
        .allow_daemon_threads = 0,
        .check_multi_interp_extensions = 0,
        .gil = PyInterpreterConfig_SHARED_GIL,
    };
    PyThreadState *command_state = NULL;
    PyStatus status = Py_NewInterpreterFromConfig(&command_state, &command_config);
    if (PyStatus_Exception(status) || command_state == NULL) {
        report_runtime_message(status.err_msg == NULL
            ? "hermes: unable to create command interpreter" : status.err_msg);
        if (owns_parent_state) {
            PyThreadState_Clear(parent_state);
            PyThreadState_DeleteCurrent();
        }
        return NULL;
    }
    *parent_state_out = parent_state;
    *owns_parent_state_out = owns_parent_state;
    return command_state;
}

static void end_command_interpreter(PyThreadState *command_state,
                                    PyThreadState *parent_state,
                                    int owns_parent_state) {
    /* CPython's interpreter teardown runs threading shutdown hooks (including
     * ThreadPoolExecutor's worker shutdown) before it checks remaining states.
     * Do not pre-wait here: that would deadlock workers whose exit sentinels
     * are only queued by those hooks. */
    Py_EndInterpreter(command_state);
    PyThreadState_Swap(parent_state);
    if (owns_parent_state) {
        PyThreadState_Clear(parent_state);
        PyThreadState_DeleteCurrent();
    }
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
        PyObject *main_module = PyImport_AddModule("__main__");
        PyObject *globals = main_module == NULL ? NULL : PyModule_GetDict(main_module);
        result = globals == NULL ? NULL
            : PyRun_FileExFlags(script, argv[1], Py_file_input,
                                globals, globals, 1, NULL);
        if (globals == NULL) fclose(script);
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
    pthread_once(&runtime_init_once, initialize_runtime_once);
    if (runtime_init_result != 0) return runtime_init_result;

    PyThreadState *parent_state = NULL;
    int owns_parent_state = 0;
    PyThreadState *command_state = begin_command_interpreter(
        &parent_state, &owns_parent_state);
    if (command_state == NULL) {
        report_runtime_message("hermes: unable to create command interpreter");
        return 70;
    }
    int result = set_command_argv(argc, argv);
    if (result == 0) {
        PyObject *bootstrap = PyImport_ImportModule("sitecustomize");
        if (bootstrap == NULL) {
            result = report_python_error("import sitecustomize");
        } else {
            Py_DECREF(bootstrap);
            result = python_mode ? run_python_command(argc, argv)
                                 : run_hermes_command(argc, argv);
        }
    }
    flush_python_stdio();
    end_command_interpreter(command_state, parent_state, owns_parent_state);
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
