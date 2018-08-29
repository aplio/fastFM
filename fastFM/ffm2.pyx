# Author: Immanuel Bayer
# License: BSD 3 clause

import json

cimport cpp_ffm
from cpp_ffm cimport Settings, Data, Model, predict, fit
from libcpp.memory cimport nullptr
from libcpp.string cimport string

import scipy.sparse as sp

cimport numpy as np
import numpy as np


cdef Settings* _settings_factory(fm):
    settings_dict = fm.get_params()
    cdef Settings* s = new Settings(json.dumps(settings_dict).encode())
    return s


def _init_parameter(fm, n_features):
    fm.w0_ = np.zeros(1, dtype=np.float64)
    fm.w_ = np.zeros(n_features, dtype=np.float64)
    fm.V_ = np.zeros((fm.rank, n_features), dtype=np.float64)
    return fm.w0_, fm.w_, fm.V_


cdef Model* _model_factory(double[:] w_0, double[:] w,
        np.ndarray[np.float64_t, ndim = 2] V):

    cdef Model *m = new Model()
    rank = V.shape[0]
    n_features = V.shape[1]
    m.add_parameter(&w_0[0])
    m.add_parameter(&w[0], n_features)
    m.add_parameter(<double *> V.data, rank, n_features, 2)

    return m


cdef Model* _model_factory_self(fm):

    n_features = fm.w_.shape[0]
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w_0 = fm.w0_
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] w = fm.w_
    cdef np.ndarray[np.float64_t, ndim=2, mode='c'] V = fm.V_

    cdef Model *m = new Model()
    rank = V.shape[0]
    n_features = V.shape[1]
    m.add_parameter(&w_0[0])
    m.add_parameter(&w[0], n_features)
    m.add_parameter(<double *> V.data, rank, n_features, 2)

    return m


cdef Data* _data_factory(X, double[:] y_pred):
    # get attributes from csc scipy
    n_features = X.shape[1]
    n_samples = X.shape[0]
    nnz = X.count_nonzero()

    if not (sp.isspmatrix_csc(X) or sp.isspmatrix_csr(X)):
        raise "matrix format is not supported"

    cdef np.ndarray[int, ndim=1, mode='c'] inner = X.indices
    cdef np.ndarray[int, ndim=1, mode='c'] outer = X.indptr
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] data = X.data

    cdef Data *d = new Data()
    d.add_design_matrix(n_samples, n_features, nnz, &outer[0], &inner[0],
                        &data[0], sp.isspmatrix_csc(X))
    d.add_prediction(n_samples, &y_pred[0])
    return d


# cython doesn't support function overloading
cdef Data* _data_factory_fit(X, double[:] y_pred,  double[:] y_true):
    d = _data_factory(X, y_pred)
    d.add_target(X.shape[0], &y_true[0])
    return d


def ffm_predict(double [:] w_0, double[:] w,
                np.ndarray[np.float64_t, ndim = 2] V, X):
    assert X.shape[1] == len(w)
    assert X.shape[1] == V.shape[1]

    # allocate memory for predictions
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] y =\
         np.zeros(X.shape[0], dtype=np.float64)

    m = _model_factory(w_0, w, V)
    d = _data_factory(X, y)

    cpp_ffm.predict(m, d)

    del m
    del d

    return y


def ffm_predict_self(fm, X):
    return ffm_predict(fm.w0_, fm.w_, fm.V_, X)


def ffm_fit(double [:] w_0, double[:] w, np.ndarray[np.float64_t, ndim = 2] V,
                X, double[:] y, int rank, dict settings):
    assert isinstance(settings, dict)
    assert X.shape[0] == len(y) # test shapes

    cdef Settings* s = new Settings(json.dumps(settings).encode())
    m = _model_factory(w_0, w, V)

    # allocate memory for prediction
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] y_pred = np.zeros(
            X.shape[0], dtype=np.float64)

    d = _data_factory_fit(X, y, y_pred)

    cpp_ffm.fit(s, m, d)

    del d
    del m
    del s

    return w_0, w, V


def ffm_fit_self(fm, X, double[:] y):
    assert X.shape[0] == len(y) # test shapes

    _init_parameter(fm, X.shape[1])
    m = _model_factory(fm.w0_, fm.w_, fm.V_)

    # allocate memory for prediction
    cdef np.ndarray[np.float64_t, ndim=1, mode='c'] y_pred = np.zeros(
            X.shape[0], dtype=np.float64)

    d = _data_factory_fit(X, y, y_pred)
    s = _settings_factory(fm)

    cpp_ffm.fit(s, m, d)


    del d
    del m
    del s

    return fm.w0_, fm.w_, fm.V_
