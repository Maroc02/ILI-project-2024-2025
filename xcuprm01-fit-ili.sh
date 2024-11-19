#!/bin/env bash

##
#  Author:  Marek Čupr (xcuprm01)
#  Subject: ILI - Project
#  Date:    12. 10. 2024
#  Description:
#      This script automates several system tasks related to loop devices, filesystems,
#      YUM package management, and Apache setup:
#
#      1. Creates a 200 MB file and formats it as an ext4 loop device.
#      2. Automates the mounting process by adding an entry to /etc/fstab and mounts the device
#         to /var/www/html/ukol.
#      3. Downloads and installs specified RPM packages via YUM into the mounted directory.
#      4. Generates YUM repository metadata and configures the system to use the repository.
#      5. Installs and starts the Apache HTTP server (httpd).
#      6. Lists all available YUM repositories and verifies the custom repository setup.
#      7. Unmounts the filesystem and verifies the unmount process with "mount -a".
#      8. Displays package information from the configured repository.
##

##############################
#     Declare Constants      #
##############################

# Array of essential packages to be intalled
declare -r ESSENTIAL_PACKAGES=("httpd" "createrepo")

# Path to the file to be created
declare -r FILE_PATH="/var/tmp/ukol.img"

# Number of blocks of the file to be created (200MB)
declare -r FILE_BLOCK_COUNT=200

# Mount point for the loop device
declare -r MOUNT_POINT_PATH="/var/www/html/ukol"

# Path to the fstab file
declare -r FSTAB_PATH="/etc/fstab"

# Exit code for successful execution
declare -r EXIT_SUCCESS=0

# Exit code for failure execution 
declare -r EXIT_FAILURE=1

##############################
#     Declare Variables      #
##############################

# Integer variable to track log entries
declare -i logIndex=1

# Variable to store the name of the created loop device
declare loopDevice

##############################
#     Logging Functions      #
##############################

##
#  @fn        log_debug_message()
#  @brief     Logs a debug message and increments the log index.
#  @param[in] $1 - The message to log.
##
function log_debug_message()
{
	echo "${logIndex}) $1"
	logIndex=$((logIndex + 1))
}

##
#  @fn        log_action_result()
#  @brief     Logs the result of an action, either success or error, and exits on failure.
#  @param[in] $1 - The exit status code from the previous command (0 for success, non-zero for failure).
#  @param[in] $2 - The message to display for success.
#  @param[in] $3 - The message to display for error if the operation fails.
##
function log_action_result()
{
    # Check if the previous command was successful
	if [[ "$1" -eq "${EXIT_SUCCESS}" ]]; then
        # Log success message
		echo "SUCCESS: $2"
	else 
        # Log error message and exit with failure code
		echo "ERROR: $3"
		exit "${EXIT_FAILURE}"
	fi

    # Print an empty line for better readability in the logs
    echo
}

#################################
#  Essential Package Functions  #
#################################

##
#  @fn        install_essential_packages()
#  @brief     Installs essential packages (httpd and createrepo) using YUM.
##
function install_essential_packages()
{
    # Iterate over each package in the ESSENTIAL_PACKAGES array
    for package in "${ESSENTIAL_PACKAGES[@]}"; do
        # Install the current package using yum
        log_debug_message "Installing essential package ${package} with yum"
        yum install -y "${package}"

        # Log the result of the installation
        log_action_result "$?" \
            "Installed essential package ${package} successfully" \
            "Failed to install essential package ${package} with yum"
    done
}

##########################################
#  Loop Device and Filesystem Functions  #
##########################################

##
#  @fn        create_loop_device()
#  @brief     Creates a file, sets up a loop device, and logs the results.
#  @details   The function creates a file of a specified size, assigns it to a loop device, 
#             and logs the results of these operations, indicating success or failure.
##
function create_loop_device()
{
    # Create a file of the specified size
	log_debug_message "Creating file ${FILE_PATH} of size ${FILE_BLOCK_COUNT}"
	dd if=/dev/zero of="${FILE_PATH}" bs=1M count="${FILE_BLOCK_COUNT}"

    # Log the result of the file creation (success or failure)
	log_action_result "$?" \
        "Created file ${FILE_PATH} of size ${FILE_BLOCK_COUNT}" \
        "Failed to create file ${FILE_PATH} of size ${FILE_BLOCK_COUNT}"

    # Create a loop device from the file
	log_debug_message "Creating loop device at first unused device"
	loopDevice=$(losetup --find --show "${FILE_PATH}")

    # Log the result of the loop device creation (success or failure)
	log_action_result "$?" \
        "Created loop device at ${loopDevice}" \
        "Failed to create loop device at ${loopDevice}"
}

##
#  @fn        create_file_system()
#  @brief     Creates a filesystem on a loop device, sets up the mount point, 
#             and updates the system configuration for automatic mounting.
#  @details   The function creates an ext4 filesystem on the specified loop device,
#             ensures the mount point directory exists, updates `/etc/fstab` for automatic mounting, 
#             and then mounts the filesystem to the specified mount point.
##
function create_file_system()
{
    # Create the filesystem (ext4) on the loop device
	log_debug_message "Creating filesystem at loop device ${loopDevice}"
	mkfs.ext4 "${loopDevice}"

    # Log the result of the filesystem creation (success or failure)
	log_action_result "$?" \
        "Created filesystem at loop device ${loopDevice}" \
        "Failed to create filesystem at loop device ${loopDevice}"

    # Ensure the mount point directory exists 
	if ! [[ -d "${MOUNT_POINT_PATH}" ]]; then
        log_debug_message "Creating mount point directory at ${MOUNT_POINT_PATH}."
		mkdir -p "${MOUNT_POINT_PATH}"

        # Log the result of creating the mount point directory (success or failure)
		log_action_result "$?" \
            "Successfully created mount point directory at ${MOUNT_POINT_PATH}." \
            "Failed to create mount point directory at ${MOUNT_POINT_PATH}."
	fi

    # Update /etc/fstab to enable automatic mounting
	log_debug_message "Updating ${FSTAB_PATH} for automatic mounting of ${MOUNT_POINT_PATH}"
	echo "${loopDevice} ${MOUNT_POINT_PATH} ext4 defaults 0 0" >> "${FSTAB_PATH}"

    # Log the result of the /etc/fstab update (success or failure)
	log_action_result "$?" \
        "Updated ${FSTAB_PATH} for automatic mounting of ${MOUNT_POINT_PATH}" \
        "Failed to update ${FSTAB_PATH} for automatic mounting of ${MOUNT_POINT_PATH}"

    # Mount the filesystem at the specified mount point
	log_debug_message "Mounting filesystem at ${loopDevice} to ${MOUNT_POINT_PATH}"
	mount "${loopDevice}" "${MOUNT_POINT_PATH}"

    # Log the result of mounting the filesystem (success or failure)
	log_action_result "$?" \
        "Mounted filesystem at ${loopDevice} to ${MOUNT_POINT_PATH}" \
        "Failed to mount filesystem at ${loopDevice} to ${MOUNT_POINT_PATH}"
}

##########################################
#  YUM Package and Repository Functions  #
##########################################

##
#  @fn        download_yum_packages()
#  @brief     Downloads specified YUM packages and stores them in the mount point.
#  @param[in] $@ - List of package names to download.
##
function download_yum_packages()
{
    # Iterate over each package name passed as argument
	for package in "$@"; do
        # Use yum to download the package to the specified directory
		log_debug_message "Downloading package ${package} with yum"
		yum install --downloadonly --downloaddir="${MOUNT_POINT_PATH}" "${package}"

        # Log the result of the download package
		log_action_result "$?" \
            "Downloaded package: ${package} with yum" \
            "Failed to download package: ${package} with yum"
	done
}

##
#  @fn        generate_repodata()
#  @brief     Creates the YUM repository metadata and updates the repository configuration.
##
function generate_repodata()
{
    # Generate repository metadata in the mount point directory
    log_debug_message "Generating repository metadata at ${MOUNT_POINT_PATH}"
	createrepo "${MOUNT_POINT_PATH}"

    # Check if createrepo succeeded
    log_action_result "$?" \
        "Generated repository metadata successfully" \
        "Failed to generate repository metadata"

    # Restore SELinux contexts for the mount point directory
    log_debug_message "Restoring SELinux context for ${MOUNT_POINT_PATH}"
	restorecon -Rv "${MOUNT_POINT_PATH}"

    # Check if restorecon succeeded
    log_action_result "$?" \
        "Restored SELinux context successfully" \
        "Failed to restore SELinux context"

    # Create the repository configuration file
    cat <<EOL > /etc/yum.repos.d/ukol.repo
[ukol]
name=Ukol Repository
baseurl=http://localhost/ukol
enabled=1
gpgcheck=0
EOL

    # Check if repository file creation was successful
    log_action_result "$?" \
        "Created ukol repository configuration file successfully" \
        "Failed to create ukol repository configuration file"
}

#################################
#  Apache and System Functions  #
#################################

##
#  @fn        start_apache()
#  @brief     Installs and starts Apache HTTP server (httpd).
##
function start_apache()
{ 
    # Start the Apache HTTP server
    log_debug_message "Starting Apache HTTP server."
	systemctl start httpd

    # Check if Apache service started successfully
    log_action_result "$?" \
        "Started Apache HTTP server successfully" \
        "Failed to start Apache HTTP server"

    # Enable Apache HTTP server to start on boot
    log_debug_message "Enabling Apache HTTP server to start on boot."
	systemctl enable httpd

    # Check if Apache service enabled successfully
    log_action_result "$?" \
        "Enabled Apache HTTP server to start on boot successfully" \
        "Failed to enable Apache HTTP server to start on boot"
}

##
#  @fn        list_yum_repositories()
#  @brief     Lists all available YUM repositories.
##
function list_yum_repositories()
{
    # Log message about listing the YUM repositories
    log_debug_message "Listing all available YUM repositories."
	yum repolist

    # Check if the repolist command was successful
    log_action_result "$?" \
        "Listed YUM repositories successfully" \
        "Failed to list YUM repositories"
}

###########################################
#  Filesystem and Package Info Functions  #
###########################################

##
#  @fn        unmount_filesystem()
#  @brief     Unmounts the filesystem at the mount point and re-mounts all entries from /etc/fstab.
#
function unmount_filesystem()
{
    # Log message about unmounting the filesystem
    log_debug_message "Unmounting filesystem at ${MOUNT_POINT_PATH}."
	umount "${MOUNT_POINT_PATH}"
    
    # Check if unmounting succeeded
    log_action_result "$?" \
        "Unmounted filesystem successfully" \
        "Failed to unmount filesystem"
   
    # Re-mount all entries in /etc/fstab
    log_debug_message "Re-mounting all entries from /etc/fstab."
	mount -a

    # Check if mounting all entries succeeded
    log_action_result "$?" \
        "Re-mounted all entries from /etc/fstab successfully" \
        "Failed to re-mount all entries from /etc/fstab"
}

##
#  @fn        display_package_information()
#  @brief     Displays information about packages from the custom YUM repository.
##
function display_package_information()
{
    # Log message about displaying package information from the ukol repository
    log_debug_message "Displaying package information from the ukol repository."
    yum --disablerepo="*" --enablerepo="ukol" list available

    # Check if the package listing succeeded
    log_action_result "$?" \
        "Displayed package information from ukol repository successfully" \
        "Failed to display package information from ukol repository"
}

##############################
#        Main Function       #
##############################

##
#  @fn        main()
#  @brief     Main function to execute the full set of tasks for creating loop devices,
#             setting up a filesystem, downloading packages, generating repository data, 
#             starting Apache, listing repositories, unmounting filesystem, and displaying
#             package information.
#  @param[in] $@ - List of package names to download.
##
function main()
{
    # Install essential packages (httpd and createrepo)
    install_essential_packages

    # Create the loop device and set it up
	create_loop_device

    # Create the filesystem on the loop device
	create_file_system

    # Download specified YUM packages (passed as arguments to the script)
	download_yum_packages "$@"

    # Generate repository data for the custom YUM repository
	generate_repodata

    # Install and start Apache HTTP server
    start_apache

    # List all available YUM repositories
    list_yum_repositories

    # Unmount the filesystem at the mount point and re-mount all entries in /etc/fstab
    unmount_filesystem

    # Display information about the packages in the custom YUM repository
    display_package_information
    
    # Exit the script successfully
	exit "${EXIT_SUCCESS}"
}

# Execute the main function with any provided arguments
main "$@"

# End of xcuprm01-fit-ili.sh
