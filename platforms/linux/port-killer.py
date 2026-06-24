#!/usr/bin/env python3
import os
import sys

# Add the directory containing the 'src' package to sys.path
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, script_dir)

from src.main import main

if __name__ == '__main__':
    main()
