import unittest
import numpy as np
import cv2
import sys


class TestGEMM(unittest.TestCase):
    def test_gemm_big(self):
        sz = (500, 500)
        a = np.ones(sz, dtype=float)
        b = np.eye(sz[0])
        c = np.ones(sz, dtype=float)
        x = cv2.gemm(a, b, 2, c, 3)
        gold = np.full(sz, 5, dtype=float)
        self.assertTrue(np.array_equal(gold, x), "Array returned by GEMM is not valid")


if __name__ == '__main__':
    unittest.main()
