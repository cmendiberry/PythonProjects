
# Run AWS DMS Assesment for all databases in any number of instances

## Folder structure


    |_\Path
        |DMSASSESSMENT
        ├── config/
        |     └── instances.txt
        ├── utils/
        |     ├── __init__.py    # Empty file to indicate this is a package
        │     |── colors.py  # Shared functions
        |     └── encryption/
        |               |── decrypt_files.py  # To decrypt connection string files manually
        |               |── encrypt_all.py   # To encrypt connection string files manually  not in the default path
        |               |── encrypt_files.py  # To encript connection string files manually in the deault path
        │               └── encryptor.py  
        |── awsdms_support_collector_sql_server.sql # script provided by aws
        └── dms_assessment.py #main script
    
## Requisites

- Install **Python 3.12**
- Install **pip3 install cryptography**
- Credentials for the migrationuserwX (X= wave number)
- The file **instances.txt** is already created in the config folder. It's possible to fill it with the target servers, or you can provide a diferent file, and send the full path as second argument to the python script.
- Either if you are using the config\instances.txt or anyother, you must comply the following requisites:
    
    
    a. **one line per instance** 
    
    b. the format must be like the ones provided as example below: (user and password will be the ones created for the migration):
    
    fqdn1,PORT1,migrationuserwX,PASSWORD
    
    fqdn2.int.abrigo.app,PORT2,migrationuserwX,PASSWORD
    
    fqdn3.int.abrigo.app,PORT2,migrationuserwX,PASSWORD
- Save it.

## Encrypt the connection string files: Path\DMSAssessments\utils\encryption>
- The instance file will be automatically encrypted when executing dms_assessment.py.
- If the key has never been createdor as deleted, it will be automatically created right before encrypting the files.
- The path to save the *encripted file(encription.key)* is defined in: **encriptor.py variable KEY_FILE** you can change it.
It will be exected Open a cmd window on the directory where the encrypt_[files | all].py is located
- To test manually, open a cmd window on the directory **Path\DMSAssessments\utils\encryption>**:
    1. If you are going to use the instances.txt located within the solution by default, then you can simply execute **Path\DMSAssessments\utils\encryption>python encrypt_files.py**
    2. If you are going to use an instances.txt located outside the solution, then you must call this script *including* the file path **Path\DMSAssessments\utils\encryption>python encrypt_all.py \<path to find the instances info>**
    3. Decryption: **Path\DMSAssessments\utils\encryption>python decrypt_files.py**
    4. This manual tests, make use of the encryptor.py functions, therefore, if you run any of the encrypt_[file | all].py, **the source file will be deleted**.

## Execution: Path\DMSASSESSMENT>python dms_assessment.py \<root folder> \<path to find the instances info>
- Open a cmd window on the directory where the python script **dms_assessment.py** is located
- Copy the root path (which is a mandatory argument) and the instances.txt file path (optional) 
- **The instance file provided will be encrypted and deleted, you can omit the deletion from the ecryptor.py -> encrypt_files function by commmenting out the lines 70 and 71**
### Execute the script: Scenario1 python dms_assessment.py \<root folder>
- You'll receive the following message:
![alt text](_images/oneArgMSG.png)

- If you write no, the execution finishes. On the other hand , by writing **yes**, you'll get the values to be use for this execution:
![alt text](_images/oneArgYes.png)

### Execute the script: Scenario2 python dms_assessment.py \<root folder> \<path to find the instances info>
- You get the informational message, and it will start executing immediately:
![alt text](_images/twoArgs.png)

## Output of the execution
1. The script will loop through the lines in the instances file
2. Will create (recreate if exists) the **DMSAssessments** folder in the path folder sent as Arg1
3. Will grab line by line, and create the subfolder for the Server and inside it, another subfolder with the port number
4. Will execute the sqlcmd for all the databases in that instance and save the result in the path generated above:
![alt text](_images/blured.png)
