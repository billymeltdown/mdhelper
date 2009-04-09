#import <Foundation/Foundation.h>

#pragma mark Constants
#define NOTEST		0
#define DEVICETEST	1 << 0
#define FNAMETEST	1 << 1
#define MDTEST		1 << 2

#define SUMMARY		0
#define SHOWFILES	1 << 0
#define SHOWMDS		1 << 1
#define SKIPV2		1 << 2
#define SKIPV3		1 << 3
#define GLOB		1 << 4


#pragma mark Backup Folder Utilities
NSString *backupDirPath()
{
	return [[[[NSHomeDirectory() stringByAppendingPathComponent:@"Library"]
			  stringByAppendingPathComponent:@"Application Support"]
			 stringByAppendingPathComponent:@"MobileSync"]
			stringByAppendingPathComponent:@"Backup"];
}

NSString *recoveryFolderPath()
{
	return [[NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"]
			stringByAppendingPathComponent:@"Recovered iPhone Files"];
}

NSArray *backupFolders()
{
	return [[NSFileManager defaultManager] directoryContentsAtPath:backupDirPath()];
}

void createRecoveryFolder ()
{
	[[NSFileManager defaultManager] createDirectoryAtPath:recoveryFolderPath() attributes:NULL];
}

#pragma mark plist utilities
void WriteMyPropertyListToFile(CFPropertyListRef propertyList, CFURLRef fileURL) 
{
	CFDataRef xmlData;
	Boolean status;
	SInt32 errorCode;
	xmlData = CFPropertyListCreateXMLData(kCFAllocatorDefault, propertyList);
	status = CFURLWriteDataAndPropertiesToResource (fileURL, xmlData, nil, &errorCode);
	CFRelease(xmlData);
}

void WriteMyPropertyListToBinaryFile(CFPropertyListRef plist,
									 CFURLRef fileURL) 
{
	CFIndex bytesWritten;
	CFWriteStreamRef stream = CFWriteStreamCreateWithFile(NULL, fileURL);
	Boolean isOpen = CFWriteStreamOpen(stream);
	if (isOpen)
	{
		bytesWritten = CFPropertyListWriteToStream(plist, stream, kCFPropertyListBinaryFormat_v1_0, NULL );
		CFWriteStreamClose(stream);
	}
}

void WriteMyDataToXMLFile(NSData *xmlData, CFURLRef fileURL)
{
	CFPropertyListRef plist = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)xmlData, kCFPropertyListMutableContainers, nil);
	WriteMyPropertyListToFile(plist, fileURL);
}

#pragma mark Manifest Utilities
void getManifests(BOOL xml)
{
	// This does not check for the existence of manifests to create new items so dupe backups
	// will overwrite each other.
	
	createRecoveryFolder();
	
	for (NSString *path in backupFolders())
	{
		NSString *fullPath = [backupDirPath() stringByAppendingPathComponent:path];
		NSString *manifestPath = [fullPath stringByAppendingPathComponent:@"Manifest.plist"];
		NSString *infoPath = [fullPath stringByAppendingPathComponent:@"Info.plist"];
		
		NSDictionary *manifestDict = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
		NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoPath];
		
		NSString *deviceName = [infoDict objectForKey:@"Device Name"];
		NSData *data = [manifestDict objectForKey:@"Data"];
		
		NSString *outfile = [[recoveryFolderPath() stringByAppendingPathComponent:deviceName] stringByAppendingString:@"-Manifest.plist"];
		if (data) printf("Extracting manifest for device %s\n", [deviceName UTF8String]);
		if (!xml)
		{
			[data writeToFile:outfile atomically:YES];
		}
		else
		{
			CFURLRef fileURL = CFURLCreateWithFileSystemPath( kCFAllocatorDefault, (CFStringRef) outfile, kCFURLPOSIXPathStyle, false);
			WriteMyDataToXMLFile(data, fileURL);
		}
	}
	
	printf("\nManifests are stored in %s\n", [recoveryFolderPath() UTF8String]);
}

#pragma mark Listing Utilities

void addPathToFileDict(NSMutableDictionary *filedict, NSString *path)
{
	if (!path) return;
	
	NSMutableArray *components = [NSMutableArray arrayWithArray:[path componentsSeparatedByString:@"/"]];
	
	NSString *last = [components lastObject];
	[components removeLastObject];
	
	NSMutableDictionary *current = filedict;
	for (NSString *each in components)
	{
		if ([current objectForKey:each])
			current = [current objectForKey:each];
		else
		{
			NSMutableDictionary *dict = [NSMutableDictionary dictionary];
			[current setObject:dict forKey:each];
			current = dict;
		}
	}
	[current setObject:last forKey:last];
}

void showFileDictHelper(NSDictionary *dict, int indent)
{
	NSArray *keys = [dict allKeys];
	for (NSString *key in keys)
	{
		for (int i = 0; i < indent*4; i++) printf(" ");
		printf("%s\n", [key UTF8String]);
		id child = [dict objectForKey:key];
		if ([child isKindOfClass:[NSDictionary class]]) showFileDictHelper(child, indent + 1);
	}
}

void showFileDict(NSDictionary *dict)
{
	showFileDictHelper(dict, 0);
}

BOOL checkmatch(NSString *item, NSString *matchphrase)
{
	BOOL match = NO;
	NSPredicate *beginPred = [NSPredicate predicateWithFormat:@"SELF beginswith[cd] %@", matchphrase];
	match = [beginPred evaluateWithObject:item];
	
	NSPredicate *containPred = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", matchphrase];
	match = match | [containPred evaluateWithObject:item];
	
	NSPredicate *matchPred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", matchphrase];
	match = match | [matchPred evaluateWithObject:item];
	
	matchPred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", [matchphrase uppercaseString]];
	match = match | [matchPred evaluateWithObject:item];

	matchPred = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", [matchphrase lowercaseString]];
	match = match | [matchPred evaluateWithObject:item];

	return match;
}

void listPlatformContents(int option, NSString *pmatchphrase, NSString *fmatchphrase)
{
	for (NSString *path in backupFolders())
	{
		NSString *fullPath = [backupDirPath() stringByAppendingPathComponent:path];
		NSString *infoPath = [fullPath stringByAppendingPathComponent:@"Info.plist"];
		NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoPath];
		NSString *deviceName = [infoDict objectForKey:@"Device Name"];
		
		BOOL isDir;
		[[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory: &isDir];
		if (!isDir) continue;
		
		BOOL pmatch = YES;
		
		if (pmatchphrase) pmatch = checkmatch(deviceName, pmatchphrase);
		if (!pmatch) continue;
			
		printf("\nDEVICE %s\n", [deviceName UTF8String]);
		printf("Directory: %s\n", [path UTF8String]);
		
		NSArray *mdArray2 = [[[NSFileManager defaultManager] directoryContentsAtPath:fullPath] pathsMatchingExtensions:[NSArray arrayWithObject:@"mdbackup"]];
		if (!(option & SKIPV2))	printf("Total 2.x files found: %d backup files\n", [mdArray2 count]);
		
		NSArray *mdArray3 = [[[NSFileManager defaultManager] directoryContentsAtPath:fullPath] pathsMatchingExtensions:[NSArray arrayWithObject:@"mdinfo"]];
		if (!(option & SKIPV3)) printf("Total 3.x files found: %d backup files\n", [mdArray3 count]);
		
		if ((option & SHOWFILES) && !(option & SKIPV2))
		{
			NSMutableDictionary *filedict = [NSMutableDictionary dictionary];
			for (NSString *eachFile in mdArray2)
			{
				NSString *mdpath = [fullPath stringByAppendingPathComponent:eachFile];
				NSDictionary *mddict = [NSDictionary dictionaryWithContentsOfFile: mdpath];	
				NSString *path = [[mddict objectForKey:@"Domain"] stringByAppendingPathComponent:[mddict objectForKey:@"Path"]];
				BOOL fmatch = YES;
				if (fmatchphrase) fmatch = checkmatch(path, fmatchphrase);
				if (fmatch) 
				{
					addPathToFileDict(filedict, path);
					if (option & SHOWMDS) printf("%s\n", [mdpath UTF8String]);
				}
			}
			printf("\n");
			showFileDict(filedict);
		}
		
		if ((option & SHOWFILES) && !(option & SKIPV3))
		{
			NSMutableDictionary *filedict = [NSMutableDictionary dictionary];
			for (NSString *eachFile in mdArray3)
			{
				NSString *mdpath = [fullPath stringByAppendingPathComponent:eachFile];
				NSDictionary *mddict = [NSDictionary dictionaryWithContentsOfFile: mdpath];	
				NSData *mdata = [mddict objectForKey:@"Metadata"];
				CFPropertyListRef plist = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)mdata, kCFPropertyListMutableContainers, nil);
				
				NSString *path = [[mddict objectForKey:@"Domain"] stringByAppendingPathComponent:[mddict objectForKey:@"Path"]];
				if (!path) path = [(NSDictionary *)plist objectForKey:@"Path"];
				BOOL fmatch = YES;
				if (fmatchphrase) fmatch = checkmatch(path, fmatchphrase);
				if (fmatch)
				{
					addPathToFileDict(filedict, path);
					if (option & SHOWMDS) printf("%s\n", [mdpath UTF8String]);
				}
			}
			printf("\n");
			showFileDict(filedict);
		}
	}
}

void fileDrillDown(NSString *from, NSString *path)
{
	if (!path) return;
	NSMutableArray *components = [NSMutableArray arrayWithArray:[path componentsSeparatedByString:@"/"]];
	// NSString *last = [components lastObject];
	[components removeLastObject];
	
	NSString *xpath = [NSString stringWithString:from];
	for (NSString *each in components)
	{
		xpath = [xpath stringByAppendingPathComponent:each];
		[[NSFileManager defaultManager] createDirectoryAtPath:xpath attributes:NULL];
	}
}



void extractPlatformContents(int option, NSString *pmatchphrase, NSString *fmatchphrase)
{
	createRecoveryFolder();
	
	for (NSString *path in backupFolders())
	{
		NSString *fullPath = [backupDirPath() stringByAppendingPathComponent:path];
		NSString *infoPath = [fullPath stringByAppendingPathComponent:@"Info.plist"];
		NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfFile:infoPath];
		NSString *deviceName = [infoDict objectForKey:@"Device Name"];
		
		BOOL isDir;
		[[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory: &isDir];
		if (!isDir) continue;
		
		BOOL pmatch = YES;
		
		if (pmatchphrase) pmatch = checkmatch(deviceName, pmatchphrase);
		if (!pmatch) continue;
		
		printf("\nDEVICE %s\n", [deviceName UTF8String]);
		NSArray *mdArray2 = [[[NSFileManager defaultManager] directoryContentsAtPath:fullPath] pathsMatchingExtensions:[NSArray arrayWithObject:@"mdbackup"]];
		NSArray *mdArray3 = [[[NSFileManager defaultManager] directoryContentsAtPath:fullPath] pathsMatchingExtensions:[NSArray arrayWithObject:@"mdinfo"]];
		int fcount = 0;
		
		NSString *devDir = [recoveryFolderPath() stringByAppendingPathComponent:deviceName];
		[[NSFileManager defaultManager] createDirectoryAtPath:devDir attributes:NULL];
		
		// extract files from the v2 
		if (!(option & SKIPV2))
		{
			for (NSString *eachFile in mdArray2)
			{
				
				NSString *mdpath = [fullPath stringByAppendingPathComponent:eachFile];
				NSDictionary *mddict = [NSDictionary dictionaryWithContentsOfFile: mdpath];	
				NSString *outpath = [[mddict objectForKey:@"Domain"] stringByAppendingPathComponent:[mddict objectForKey:@"Path"]];

				BOOL fmatch = YES;
				if (fmatchphrase) fmatch = checkmatch(outpath, fmatchphrase);
				if (fmatch) 
				{
					NSDictionary *mddict = [NSDictionary dictionaryWithContentsOfFile: mdpath];	
					NSData *data = [mddict objectForKey:@"Data"];
					
					int i = 1;
					if (!(option & GLOB))
					{
						NSString *testpath = [[recoveryFolderPath() stringByAppendingPathComponent:deviceName] stringByAppendingPathComponent:outpath];
						NSString *ext = [testpath pathExtension];
						NSString *basePath = [testpath stringByDeletingPathExtension];
						while ([[NSFileManager defaultManager] fileExistsAtPath:testpath])
							testpath = [NSString stringWithFormat:@"%@-%d.%@", basePath, i++, ext];
						fileDrillDown(devDir, outpath);
						[data writeToFile:testpath atomically:YES];
					}
					else
					{
						NSString *testpath = [[recoveryFolderPath() stringByAppendingPathComponent:deviceName] stringByAppendingPathComponent:[outpath lastPathComponent]];
						NSString *ext = [testpath pathExtension];
						NSString *basePath = [testpath stringByDeletingPathExtension];
						while ([[NSFileManager defaultManager] fileExistsAtPath:testpath])
							testpath = [NSString stringWithFormat:@"%@-%d.%@", basePath, i++, ext];
						[data writeToFile:testpath atomically:YES];
					}
					fcount++;
				}
			}
			printf("\n");
		}
		
		if (!(option & SKIPV3))
		{
			for (NSString *eachFile in mdArray3)
			{
				NSString *mdpath = [fullPath stringByAppendingPathComponent:eachFile];
				NSDictionary *mddict = [NSDictionary dictionaryWithContentsOfFile: mdpath];	
				NSData *mdata = [mddict objectForKey:@"Metadata"];
				NSDictionary *plist = (NSDictionary *)CFPropertyListCreateFromXMLData(kCFAllocatorDefault, (CFDataRef)mdata, kCFPropertyListMutableContainers, nil);
				NSString *outpath = [[mddict objectForKey:@"Domain"] stringByAppendingPathComponent:[mddict objectForKey:@"Path"]];
				if (!outpath) outpath = [[plist objectForKey:@"Domain"] stringByAppendingPathComponent:[plist objectForKey:@"Path"]];
				
				BOOL fmatch = YES;
				if (fmatchphrase) fmatch = checkmatch(outpath, fmatchphrase);
				if (fmatch)
				{
					NSString *secondarypath = [[mdpath stringByDeletingPathExtension] stringByAppendingPathExtension:@"mddata"];
					NSData *data = [NSData dataWithContentsOfFile:secondarypath];
					if (!data) continue;
					
					int i = 1;
					if (!(option & GLOB)) 
					{
						NSString *testpath = [[recoveryFolderPath() stringByAppendingPathComponent:deviceName] stringByAppendingPathComponent:outpath];
						NSString *ext = [testpath pathExtension];
						NSString *basePath = [testpath stringByDeletingPathExtension];
						
						while ([[NSFileManager defaultManager] fileExistsAtPath:testpath])
							testpath = [NSString stringWithFormat:@"%@-%d.%@", basePath, i++, ext];
						fileDrillDown(devDir, outpath);
						[data writeToFile:testpath atomically:YES];
					}
					else
					{
						NSString *testpath = [[recoveryFolderPath() stringByAppendingPathComponent:deviceName] stringByAppendingPathComponent:[outpath lastPathComponent]];
						NSString *ext = [testpath pathExtension];
						NSString *basePath = [testpath stringByDeletingPathExtension];
						while ([[NSFileManager defaultManager] fileExistsAtPath:testpath])
							testpath = [NSString stringWithFormat:@"%@-%d.%@", basePath, i++, ext];
						[data writeToFile:testpath atomically:YES];
					}
					fcount++;
				}
			}
		}
		printf("Recovered %d files from %s\n", fcount, [deviceName UTF8String]);
	}
}

#pragma mark User Info
void usage ()
{
	//      12345678901234567890123456789012345678901234567890123456789012345678901234567890
	printf("mdhelper now supports both 2.x and 3.x backups\n\n");
	printf("Usage: mdhelper options\n");
	printf("-help			show this message\n");
	printf("-dir			show the backup directory\n");
	printf("-summary		show summary for each platform\n");
	printf("-list			list all files for each platform\n");
	
	printf("-platform matchphrase	limit results to matching platforms\n");
	printf("-files matchphrase	limit results to matching files\n");
	
	printf("-skipv2			skip 2.x backups\n");
	printf("-skipv3			skip 3.x backups\n");

	printf("-manifests		recover manifests and store on desktop\n");
	printf("-xml			request property list output in XML format\n");
	printf("-binary			request property list output in binary format\n");
	
	printf("-extract		extract files and store on desktop\n");
	printf("-glob			do not preserve the file structure when extracting files\n");
	
	printf("\n");
	printf("About matching:\n");
	printf("When matching, supply a short phrase or regular expresson. Regexps must\n");
	printf("match the entire item name. e.g. '.a' will match Ba but not Bologna while\n");
	printf("'.*a' will match both. Non regular expressions are compared for 'containment'\n");
	printf("so 'a' will match Ba, Bar, Abar, and Bologna.\n");
}

void showbudir ()
{
	printf("%s\n", [backupDirPath() UTF8String]);
}

int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	if (argc == 1)
	{
		usage();
		exit(1);
	}
	
	NSArray *args = [[NSProcessInfo processInfo] arguments];
	NSPredicate *pred = [NSPredicate predicateWithFormat:@"SELF beginswith '-'"];
	NSArray *dashedArgs = [args filteredArrayUsingPredicate:pred];
	BOOL isXML = NO;
	int skips = 0;
	NSString *pmatchphrase = nil;
	NSString *fmatchphrase = nil;
	
	// Scan for settings
	for (NSString *darg in dashedArgs)
	{
		if ([darg caseInsensitiveCompare:@"-xml"] == NSOrderedSame) 
		{
			isXML = YES; 
			printf("Setting plist output style to XML.\n");
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-binary"] == NSOrderedSame) 
		{
			isXML = NO; 
			printf("Setting plist output style to binary.\n");
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-platform"] == NSOrderedSame) 
		{
			pmatchphrase = [[NSUserDefaults standardUserDefaults] objectForKey:@"platform"];
			printf("Setting platform match phrase to %s.\n", [pmatchphrase UTF8String]);
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-files"] == NSOrderedSame) 
		{
			fmatchphrase = [[NSUserDefaults standardUserDefaults] objectForKey:@"files"];
			printf("Setting file match phrase to %s.\n", [fmatchphrase UTF8String]);
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-skipv2"] == NSOrderedSame) 
		{
			skips = skips | SKIPV2;
			printf("Skipping 2.x backup files.\n");
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-skipv3"] == NSOrderedSame) 
		{
			skips = skips | SKIPV3;
			printf("Skipping 3.x backup files.\n");
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-glob"] == NSOrderedSame) 
		{
			skips = skips | GLOB;
			printf("Will extract all files to top level folders\n");
			continue;
		}
	}
	
	// Scan for actions
	for (NSString *darg in dashedArgs)
	{
		if ([darg caseInsensitiveCompare:@"-help"] == NSOrderedSame) {usage(); continue;}

		if ([darg caseInsensitiveCompare:@"-dir"] == NSOrderedSame)  {showbudir(); continue;}
		if ([darg caseInsensitiveCompare:@"-directory"] == NSOrderedSame)  {showbudir(); continue;}

		if ([darg caseInsensitiveCompare:@"-manifests"] == NSOrderedSame)  {getManifests(isXML); continue;}
		
		if ([darg caseInsensitiveCompare:@"-summary"] == NSOrderedSame)  
		{
			listPlatformContents(SUMMARY | skips, pmatchphrase, fmatchphrase); 
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-list"] == NSOrderedSame)  
		{
			listPlatformContents(SHOWFILES | skips, pmatchphrase, fmatchphrase); 
			continue;
		}
		if ([darg caseInsensitiveCompare:@"-extract"] == NSOrderedSame)  
		{
			extractPlatformContents(skips, pmatchphrase, fmatchphrase); 
			continue;
		}
	}
	
	printf("Done.\n");
	
    [pool drain];
    return 0;
}
