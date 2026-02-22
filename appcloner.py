import os
import platform
import plistlib
import shutil
import zipfile
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

from utils.executor import execute
from utils.logger import get_logger
from utils.string_mutator import mutate

if platform.machine() == "arm64":
    LDID_BINARY_NAME = "ldid_arm64"
else:
    LDID_BINARY_NAME = "ldid_x64"

logger = get_logger(__name__)
__version__ = "1.6"

class AppCloner:
    """A Library for generating IPA's with seperate Keychain and Shared App access"""

    working_directory: Path

    def __init__(self, input_path: Path, output_path: Path, seed: str = None, bundle_id: str = None,
                 verbose: bool = False, use_original_team_id: bool = False, config=None, clone_uuid=uuid4()):
        logger.info("Starting version %s" % __version__)
        logger.info("Clonning with config: " + str(config))
        self.working_directory = Path(__file__).parent
        self.input_path = input_path
        self.output_path = output_path
        self.temp_dir = Path("temp_appcloner")
        self.patches_dir = self.working_directory / "patches_dir"
        self.tmp_app_folder = ""
        self.new_binary = ""
        self.new_bundle_id = ""
        self.clone_uuid = str(clone_uuid)
        # Create consistent hash from seed
        seed_hash = sha256(str(seed).encode()).hexdigest()
        self.seed = str(seed)
        self.bundle_id = bundle_id
        self.team_id = seed_hash[-10:].upper()
        self.verbose = verbose
        self.use_original_team_id = use_original_team_id
        self.original_binary = None
        self.config = config
        self.lib_dir = Path("lib")  # Directory for hooking libraries
        self.no_inject_hl = False  # Flag to control hooking library injection
        self.raw_entitlements = None

    def _inject_hooking_library(self):
        """Inject CydiaSubstrate or libsubstitute as the hooking library using optool"""
        if self.no_inject_hl:
            logger.info("Skipping hooking library injection as requested")
            return

        # Create Frameworks directory in app bundle
        frameworks_dir = self.tmp_app_folder / "Frameworks"
        frameworks_dir.mkdir(exist_ok=True)

        # Define hooking libraries in order of preference
        hooking_libraries = [
            ("CydiaSubstrate.framework", True),  # (framework_name, is_framework)
            ("libsubstitute.dylib", False)
        ]

        # First, strip code signature from the binary
        ldid_path = self.working_directory / LDID_BINARY_NAME
        command = f"{ldid_path} -r {self.new_binary}"
        execute(command, self.working_directory)
        logger.debug("Stripped code signature from binary")

        optool_path = self.working_directory / "optool"

        for lib_name, is_framework in hooking_libraries:
            source_path = self.working_directory / self.lib_dir / lib_name
            if not source_path.exists():
                logger.debug(f"Hooking library {lib_name} not found, trying next option")
                continue

            if is_framework:
                # Handle framework
                framework_dir = frameworks_dir / lib_name
                if framework_dir.exists():
                    shutil.rmtree(framework_dir)
                
                # Copy the entire framework structure
                shutil.copytree(source_path, framework_dir)

                # Get the actual binary name from Info.plist
                info_plist_path = framework_dir / "Info.plist"
                if info_plist_path.exists():
                    with open(info_plist_path, 'rb') as f:
                        info = plistlib.load(f)
                    binary_name = info.get('CFBundleExecutable', lib_name.replace('.framework', ''))
                else:
                    binary_name = lib_name.replace('.framework', '')

                framework_binary = framework_dir / binary_name
                install_name = f"@executable_path/Frameworks/{lib_name}/{binary_name}"

                # Use optool to install the framework
                command = f"{optool_path} install -c load -p {install_name} -t {self.new_binary}"
                execute(command, self.working_directory)
                logger.debug(f"Used optool to inject framework: {install_name}")

                # Sign the framework binary
                command = f"{ldid_path} -S {framework_binary}"
                execute(command, self.working_directory)
                logger.debug(f"Signed framework binary: {framework_binary}")

            else:
                # Handle regular dylib
                dylib_path = frameworks_dir / lib_name
                shutil.copy2(source_path, dylib_path)
                install_name = f"@executable_path/Frameworks/{lib_name}"

                # Use optool to install the dylib
                command = f"{optool_path} install -c load -p {install_name} -t {self.new_binary}"
                execute(command, self.working_directory)
                logger.debug(f"Used optool to inject dylib: {install_name}")

            # Re-sign the main binary after modifications
            command = f"{ldid_path} -S {self.new_binary}"
            execute(command, self.working_directory)
            logger.debug("Re-signed main binary after modifications")
            
            logger.info(f"Successfully injected {lib_name} as hooking library")
            return True

        logger.warning("No hooking library could be injected")
        return False
    def generate_clone(self):
        """Main function to duplicate an IPA, modify the bundle ID, entitlements, and repackage."""
        try:
            with TemporaryDirectory() as tmp_dir:
                self.temp_dir = Path(tmp_dir)
                self._extract_ipa()
                self.raw_entitlements = self._get_original_entitlements()
                self.orig_team_id = self.raw_entitlements.get('com.apple.developer.team-identifier', self.team_id)

                if not self.use_original_team_id:
                    self.team_id = sha256(self.seed.encode()).hexdigest()[-10:].upper()
                    logger.debug(f"Generating teamID {self.team_id}")
                else:
                    self.team_id = self.raw_entitlements.get('com.apple.developer.team-identifier', self.team_id)

                self._modify_plist()
                self._inject_dylib()
                self._modify_entitlements()
                self._modify_extensions()
                self._repack_ipa()
                logger.info(f"IPA cloned successfully with new bundle ID: {self.new_bundle_id}")
        except Exception as e:
            logger.error(f"An error occurred: {e}")
            raise

    def _extract_ipa(self):
        """Extract IPA and identify the original binary"""
        with zipfile.ZipFile(self.input_path, 'r') as ipa_zip:
            ipa_zip.extractall(self.temp_dir)
            self.tmp_app_folder = next(self.temp_dir.glob("Payload/*.app"), None)

        plist_path = self.tmp_app_folder / "Info.plist"
        with plist_path.open('rb') as plist_file:
            plist_data = plistlib.load(plist_file)

        app_name = plist_data.get("CFBundleExecutable")
        self.original_binary = self.tmp_app_folder / app_name
        logger.info("IPA file extracted successfully.")

    def _generate_team_id(self):
        """Generate or extract team ID"""
        if self.use_original_team_id:
            original_entitlements = self._get_original_entitlements()
            self.team_id = original_entitlements.get('com.apple.developer.team-identifier', '')
        else:
            hashed_str = sha256(self.seed.encode()).hexdigest().upper()
            self.team_id = hashed_str[-10:]

        logger.info(f"Team ID: {self.team_id}")

    def _get_original_entitlements(self):
        """Retrieve original entitlements"""
        entitlements_raw = self.get_entitlements(self.original_binary)
        try:
            return plistlib.loads(entitlements_raw.encode('utf-8'))
        except Exception:
            return {}

    def _modify_plist(self):
        """Modify the Info.plist file, Bundle ID and bundle name and the config for proxy and location is injected here"""
        plist_path = self.tmp_app_folder / "Info.plist"
        with plist_path.open('rb') as plist_file:
            plist_data = plistlib.load(plist_file)

        original_bundle_id = plist_data.get("CFBundleIdentifier")
        # original_app_identifier = plist_data['CFBundleIdentifier'] #original_bundle_id.split('.')[-1]
        seed_hash = sha256(self.seed.encode()).hexdigest()

        # if self.bundle_id:
        #     self.new_bundle_id = f"com.appcloner.{self.bundle_id}.{original_app_identifier}"
        # else:
        #     self.new_bundle_id = f"com.appcloner.{seed_hash[:10]}.{original_app_identifier}"
        self.new_bundle_id = mutate(original_bundle_id, int(self.seed))
        plist_data["CFBundleIdentifier"] = self.new_bundle_id
        plist_data["cloneUUID"] = self.clone_uuid

        try:
            originalName = plist_data["CFBundleDisplayName"]
            plist_data["CFBundleDisplayName"] = (
                originalName + " "+ str(self.seed)
            )
        except KeyError:
            originalName = plist_data["CFBundleName"]
            plist_data["CFBundleName"] = (
                originalName + " "+ str(self.seed)
            )


        logger.debug(f"Modifying display name to {originalName + ' ' + str(self.seed)}")

        # A config to store the original data to be spoofed by appcloner dylib
        if self.config:
            plist_data["appClonerConfig"] = self.config['appClonerConfig']
            plist_data['appClonerConfig']['keychainAccessGroup'] = [f"{self.team_id}.{self.new_bundle_id}"]
            plist_data["appClonerConfig"]["originalBundleId"] = original_bundle_id
            plist_data["appClonerConfig"]['bundleName'] = originalName
            plist_data["appClonerConfig"]['cloneUUID'] = self.clone_uuid
            plist_data['appClonerConfig']['original_team_id'] = self.orig_team_id
            plist_data['appClonerConfig']['index'] = self.seed
        # Identify the binary
        app_name = plist_data.get("CFBundleExecutable")
        self.new_binary = self.tmp_app_folder / app_name

        with plist_path.open('wb') as plist_file:
            plistlib.dump(plist_data, plist_file)

        logger.info(f"Bundle ID modified to: {self.new_bundle_id}")

    def _modify_extensions(self):
        """Modify bundle IDs of app extensions"""
        appex_files = list(self.tmp_app_folder.glob("**/*.appex"))

        for appex in appex_files:
            plist_path = appex / "Info.plist"
            if not plist_path.exists():
                continue

            with plist_path.open('rb') as plist_file:
                plist_data = plistlib.load(plist_file)

            original_extension_bundle_id = plist_data.get("CFBundleIdentifier", "")
            new_extension_bundle_id = f"{self.new_bundle_id}.{original_extension_bundle_id.split('.')[-1]}"

            plist_data["CFBundleIdentifier"] = new_extension_bundle_id
            plist_data["com.apple.developer.team-identifier"] = self.team_id
            plist_data["application-identifier"] = f"{self.team_id}.{new_extension_bundle_id}"

            with plist_path.open('wb') as plist_file:
                plistlib.dump(plist_data, plist_file)

            logger.info(f"Extension bundle ID modified: {original_extension_bundle_id} -> {new_extension_bundle_id}")

    def _modify_entitlements(self):
        """Retrieve and modify entitlements with unique app container"""
        # entitlements_raw = self.raw_entitlements
        # if self.verbose:
        #     logger.info("Original entitlements: " + str(entitlements_raw))
        entitlements = self.raw_entitlements
        container_identifier = f"group.{self.team_id}.{self.new_bundle_id}.container"

        # Update entitlements
        entitlements["application-identifier"] = f"{self.team_id}.{self.new_bundle_id}"
        entitlements["com.apple.developer.team-identifier"] = self.team_id
        entitlements["keychain-access-groups"] = [f"{self.team_id}.{self.new_bundle_id}"]
        entitlements["com.apple.security.application-groups"] = [
            f"group.{self.new_bundle_id}",
            container_identifier
        ]

        # Add container access
        entitlements["com.apple.developer.icloud-container-identifiers"] = [container_identifier]
        entitlements["com.apple.developer.icloud-container-environment"] = "production"
        # entitlements["com.apple.developer.icloud-services"] = ["CloudKit"]
        entitlements["com.apple.developer.ubiquity-container-identifiers"] = [container_identifier]
        entitlements["com.apple.security.application"] = True
        # Remove associated domains
        entitlements.pop("com.apple.developer.associated-domains", None)

        self._write_entitlements(entitlements)
        if self.verbose:
            logger.info("Updating entitlements with: " + str(entitlements))
        logger.info("Entitlements modified successfully with unique app container.")

    def _inject_dylib(self):
        """Inject all dylibs from patches directory into the binary, ensuring libsubstrate.dylib loads first."""
        if not self.patches_dir.exists():
            logger.error(f"Patches directory not found at {self.patches_dir}")
            raise FileNotFoundError(f"Patches directory not found at {self.patches_dir}")
        hooking_lib_injected = self._inject_hooking_library()

        # Create Dylibs directory in the app bundle
        dylib_dir_path = self.tmp_app_folder / "Dylibs"
        dylib_dir_path.mkdir(parents=True, exist_ok=True)

        # Get all .dylib files from patches directory
        dylib_files = list(self.patches_dir.glob("*.dylib"))

        if not dylib_files:
            logger.warning("No dylib files found in patches directory")
            return

        dylib_files = sorted(dylib_files, key=lambda x: x.name != "libsubstrate.dylib")

        # Copy and inject each dylib
        for dylib_path in dylib_files:
            # Copy dylib to app bundle
            shutil.copy(dylib_path, dylib_dir_path)

            # Determine dylib name for injection
            if dylib_path.name == "libsubstrate.dylib":
                dylib_name = "@rpath/Dylibs/libsubstrate.dylib"
            else:
                dylib_name = f"@executable_path/Dylibs/{dylib_path.name}"

            # Inject dylib using optool
            optool_path = self.working_directory / "optool"
            optool_command = f"{optool_path} install -c reexport -p {dylib_name} -t {self.new_binary}"
            execute(optool_command, self.working_directory)
            logger.info(f"Successfully injected {len(dylib_files)} dylibs")

    def _write_entitlements(self, updated_entitlements: dict):
        """Write updated entitlements to binary"""
        plist_bytes = plistlib.dumps(updated_entitlements, fmt=plistlib.FMT_XML)
        ent_path = self.temp_dir / "updated_entitlements.plist"

        with ent_path.open("wb") as temp_file:
            temp_file.write(plist_bytes)

        ldid_path = self.working_directory / LDID_BINARY_NAME
        command = f"{ldid_path} -S{ent_path} {self.new_binary}"
        execute(command, self.working_directory)

    def _repack_ipa(self):
        """Repackage modified contents into a new IPA"""
        if self.output_path.suffix == ".ipa" or self.output_path.suffix == ".tipa":
            logger.info(f"Output path is a valid .ipa file: {self.output_path}")
            output_directory = self.output_path.parent
            if not output_directory.exists():
                logger.info(f"Creating output directory: {output_directory}")
                output_directory.mkdir(parents=True, exist_ok=True)
            output_ipa_path = self.output_path
        elif self.output_path.is_dir() or not self.output_path.exists():
            if not self.output_path.exists():
                self.output_path.mkdir(parents=True, exist_ok=True)
                logger.info(f"Created output directory at {self.output_path}")
            output_ipa_path = self.output_path / self.input_path.name
        else:
            logger.error(f"Output path {self.output_path} is invalid.")
            raise ValueError(f"Invalid output path: {self.output_path}.")

        with zipfile.ZipFile(output_ipa_path, 'w', zipfile.ZIP_DEFLATED) as new_ipa_zip:
            for root, _, files in os.walk(self.temp_dir):
                for file in files:
                    file_path = Path(root) / file
                    archive_path = file_path.relative_to(self.temp_dir)
                    new_ipa_zip.write(file_path, archive_path)

        logger.info(f"Repacked IPA saved to {output_ipa_path}")

    def get_entitlements(self, binary_path: Path) -> str:
        """Retrieve entitlements from a binary"""
        ldid_path = self.working_directory / LDID_BINARY_NAME
        command = f"{ldid_path} -e {binary_path}"
        return execute(command, self.working_directory)
