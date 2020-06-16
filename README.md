# EndpointSecurity


#Steps After Cloning Repo and checking out the 'maju' branch:

 - I recommend running this on a Mac VM. Otherwise you can risk security.
 - Reboot your machine into recovery mode (Hold down CMD>R when booting up).
 - When booted into recovery mode, open utilies>terminal
 - Enter command `csrutil disable` into terminal
 - Enter `nvram boot-args="amfi_get_out_of_my_way=0x1"` into terminal
 - reboot normally.
 - after logging in to account on mac....open a terminal and enter `csrutil status`. It should yield `System Integrity Protection status: disabled.`
 - If it is `enabled` you didn't not disable SIP, you need to go back and do that again.
 
 
 - Open X code project `hydrate_cmd`
 - In the `main` function of hydrate_cmd.mm, change `targetDir` to be a file directory path on your computer. Make sure it ends in a '/'
 - In the `dispatch_sleep` function of hydrate_cmd.mm, change seconds to what ever value you want to sleep.
 
 - Build the project.
 - Run the built exe with sudo.
 
 
 - Try to open a file in the `targetDir`.
    - if the `seconds` value is less than 60 seconds, it should eventually deny the open request.
    - if it is greater than 60 seconds, than the file will still open because the deadline has passed. 
    - The problem is that we need to extend this deadline somehow.
