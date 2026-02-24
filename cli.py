import argparse
import random
import sys
from pathlib import Path

from appcloner import AppCloner
from utils.logger import get_logger

logger = get_logger(__name__)


def main():
    parser = argparse.ArgumentParser(description="Clone an IPA file with a modified bundle ID.")
    parser.add_argument("input_path", type=str, help="Path to the input IPA file.")
    parser.add_argument("output_path", type=str, help="Path to save the cloned IPA file.")
    parser.add_argument(
        "--seed",
        type=str,
        default=None,
        help="Seed for cloning operation (default: random).",
    )

    args = parser.parse_args()

    if args.seed is None:
        args.seed = random.randint(1, 99)

    cloner = AppCloner(
        input_path=Path(args.input_path),
        output_path=Path(args.output_path),
        seed=args.seed,
    )

    try:
        cloner.generate_clone()
        logger.info("Cloning successful. Check the output path for the cloned IPA.")
    except Exception as e:
        logger.error(f"An error occurred during cloning: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()