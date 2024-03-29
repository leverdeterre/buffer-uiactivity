//
//  BufferSheetViewController.m
//  BufferUIActivity
//
//  Created by Andrew Yates on 14/06/2012.
//  Copyright (c) 2012 Buffer Inc. All rights reserved.
//

#import "BufferSheetViewController.h"
#import "ProfilesService.h"
#import "PostUpdateService.h"
#import "ConfigurationService.h"
#import "ShortenLinkService.h"
#import "TwitterText.h"
#import "ProfileCell.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "GTMOAuth2SignIn.h"

@implementation BufferSheetViewController

// Add your Buffer Client ID and Secret Here
static NSString *clientID = @"";
static NSString *clientSecret = @"";
static BOOL linkShorteningEnabled = YES;

@synthesize bufferUIActivityDelegate, bufferSheetContainer, bufferAddButton, bufferSheetErrorView, bufferSheetErrorLabel, bufferSheetBackground, bufferTextViewContainer, bufferTextView, bufferProfileSelectionView, bufferProfileSelectionTable, bufferConfiguration, bufferProfiles, bufferCharLabel, bufferTextCopy, bufferProfileCountLabel, bufferCache, bufferCharacterCountOrder, avatar1Container, avatar2Container, avatar3Container, avatarView1, avatarView2, avatarView3, profileSelectionActive;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    bufferTextView.backgroundColor = [UIColor clearColor];
    
    [bufferTextView becomeFirstResponder];
    
    profileSelectionActive = YES;
    
    bufferCache = [[CachingMethods alloc] init];
    
    self.bufferProfiles = [[NSMutableArray alloc] init];
    self.bufferConfiguration = [[NSMutableDictionary alloc] init];
    self.selectedProfiles = [[NSMutableArray alloc] init];
    self.selectedProfilesIndexes = [[NSMutableArray alloc] init];
    
    if(bufferTextCopy){
        bufferTextView.text = bufferTextCopy;
        if(linkShorteningEnabled){
            [self shortenLinks];
        }
    }
        
    [self performSelector:@selector(animateSheetIn) withObject:nil afterDelay:0.4];
    
    self.bufferActiveCharacterCount = @"";
    
    if(![[NSUserDefaults standardUserDefaults] stringForKey:@"buffer_accesstoken"]){
        [self performSelector:@selector(presentAuth) withObject:nil afterDelay:0.1];
    } else {
        [NSThread detachNewThreadSelector:@selector(getConfiguration) toTarget:self withObject:nil];
    }
}

-(void)viewWillAppear:(BOOL)animated {
    self.navigationController.navigationBarHidden = TRUE;
}

-(void)animateSheetIn {
    [bufferSheetContainer setHidden:NO];
    
    [UIView animateWithDuration:0.3 animations:^{
        bufferSheetContainer.frame = CGRectMake(0, 0, 320, 245);
    } completion:^(BOOL finished) {
        [bufferProfileSelectionView setHidden:NO];
        [avatar1Container setHidden:NO];
        [avatar2Container setHidden:NO];
        [avatar3Container setHidden:NO];
    }];
}


#pragma mark - Buffer OAuth

-(GTMOAuth2Authentication *)authForBuffer {
    
    NSURL *tokenURL = [NSURL URLWithString:@"https://api.bufferapp.com/1/oauth2/token.json"];
    
    NSString *redirectURI = @"urn:ietf:wg:oauth:2.0:oob";
    
    GTMOAuth2Authentication *auth;
    auth = [GTMOAuth2Authentication authenticationWithServiceProvider:@"Buffer"
                                                             tokenURL:tokenURL
                                                          redirectURI:redirectURI
                                                             clientID:clientID
                                                         clientSecret:clientSecret];
    
    return auth;
}

-(void)presentAuth {
    GTMOAuth2Authentication *auth = [self authForBuffer];
    
    NSURL *authURL = [NSURL URLWithString:@"https://bufferapp.com/oauth2/authorize"];
    
    SEL sel = @selector(oauth2ViewController:finishedWithAuth:error:);
    
    GTMOAuth2ViewControllerTouch *viewController;
    viewController = [GTMOAuth2ViewControllerTouch controllerWithAuthentication:auth
                                                               authorizationURL:authURL
                                                               keychainItemName:nil
                                                                       delegate:self
                                                               finishedSelector:sel];
    
    [viewController setBrowserCookiesURL:[NSURL URLWithString:@"https://bufferapp.com/"]];
    
    self.navigationController.navigationBarHidden = NO;
    
    [self.navigationController pushViewController:viewController animated:NO];
    
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    viewController.navigationItem.leftBarButtonItem = backButton;
}

- (void)oauth2ViewController:(GTMOAuth2ViewControllerTouch *)viewController
            finishedWithAuth:(GTMOAuth2Authentication *)auth
                       error:(NSError *)error {
    if (error != nil) {
        NSLog(@"Error: %@", error);
    } else {
        
        NSUserDefaults *accountAccessToken = [NSUserDefaults standardUserDefaults];
        [accountAccessToken setObject:auth.accessToken forKey:@"buffer_accesstoken"];
        [accountAccessToken synchronize];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"tokenRetrieved" object:nil];
        
        [NSThread detachNewThreadSelector:@selector(getConfiguration) toTarget:self withObject:nil];
    }
}

#pragma mark - Get Configuration

-(void)getConfiguration {
    @autoreleasepool {
        if([bufferCache getCachedConfiguration]){
            self.bufferConfiguration = [[bufferCache getCachedConfiguration] mutableCopy];
            
            // Set up for character count order.
            [self loadConfiguration:self.bufferConfiguration];
        }
        
        ConfigurationService *service = [[ConfigurationService alloc] init];
        [service getConfigurationWithSender:self];
    }
}

-(void)loadConfiguration:(NSMutableDictionary *)loaded_configuration {
    if(![self.bufferConfiguration isEqual: loaded_configuration]){
        self.bufferConfiguration = loaded_configuration;
        [bufferCache cacheConfiguration:self.bufferConfiguration];
    }
    
    // Get services and load Character counts. Reiterate over them to order them smallest to biggest which we'll then use to activate the correct count.
    NSMutableArray *services = [self.bufferConfiguration valueForKey:@"services"];
    NSArray *serviceNames = [[self.bufferConfiguration valueForKey:@"services"] allKeys];
    NSMutableArray *serviceTypeNames = [[NSMutableArray alloc] init];
    NSMutableArray *serviceCharacterCounts = [[NSMutableArray alloc] init];
    
    for(NSString *service in serviceNames){
        for(NSString *type in [[services valueForKey:service] valueForKey:@"types"]){
            [serviceTypeNames addObject:[[[[[self.bufferConfiguration valueForKey:@"services"] valueForKey:service] valueForKey:@"types"] valueForKey:type] valueForKey:@"name"]];
            [serviceCharacterCounts addObject:[[[[[self.bufferConfiguration valueForKey:@"services"] valueForKey:service] valueForKey:@"types"] valueForKey:type] valueForKey:@"character_limit"]];
            
        }
    }
    
    // Tidy this up!
    NSDictionary *dataSourceDict = [NSDictionary dictionaryWithObjects:serviceCharacterCounts forKeys:serviceTypeNames];
    
    self.bufferCharacterCount = (NSMutableArray *)dataSourceDict;
    
    NSSortDescriptor *scoreSort = [NSSortDescriptor sortDescriptorWithKey:@"COUNT" ascending:YES];
    NSSortDescriptor *wordSort = [NSSortDescriptor sortDescriptorWithKey:@"SERVICE" ascending:NO];
    NSArray *sorts = [NSArray arrayWithObjects:scoreSort, wordSort, nil];
    
    
    NSMutableArray *unsortedArrayOfDict = [NSMutableArray array];
    
    for (NSString *word in dataSourceDict) {
        NSString *score = [dataSourceDict objectForKey:word];
        [unsortedArrayOfDict addObject: [NSDictionary dictionaryWithObjectsAndKeys:word, @"SERVICE", score, @"COUNT",  nil]];
    }
    
    NSArray *sortedArrayOfDict = [unsortedArrayOfDict sortedArrayUsingDescriptors:sorts];
    
    NSDictionary *sortedDict = [sortedArrayOfDict valueForKeyPath:@"SERVICE"];
    
    self.bufferCharacterCountOrder = (NSArray *)sortedDict;
    
    [NSThread detachNewThreadSelector:@selector(getProfiles) toTarget:self withObject:nil];
}


#pragma mark - Get Profiles

-(void)getProfiles {
    @autoreleasepool {
        // Load Cached Profiles
        if([self.bufferCache getCachedProfiles]){
            self.bufferProfiles = [self.bufferCache getCachedProfiles];
            [NSThread detachNewThreadSelector:@selector(loadBufferProfilesIntoView) toTarget:self withObject:nil];
        }
        
        // Reload Profiles
        ProfilesService *service = [[ProfilesService alloc] init];
        [service getBufferProfiles:self];
    }
}

-(void)loadBufferProfiles:(NSMutableArray *)loaded_profiles {
    if(![self.bufferProfiles isEqualToArray: loaded_profiles]){
        self.bufferProfiles = loaded_profiles;
        [bufferCache cacheProfileList:self.bufferProfiles];
        
        [NSThread detachNewThreadSelector:@selector(loadBufferProfilesIntoView) toTarget:self withObject:nil];
    }
}

-(void)loadBufferProfilesIntoView {
    @autoreleasepool {
        
        [self.selectedProfiles removeAllObjects];
        [self.selectedProfilesIndexes removeAllObjects];
        
        // Select Default Profiles
        for (int i = 0; i < self.bufferProfiles.count; i++) {
            NSString *avatar = [[bufferProfiles objectAtIndex:i] valueForKey:@"avatar"];
            
            
            NSString *imagePath = [NSString stringWithFormat:@"%@/%@", [bufferCache offlineCachePath], [[self.bufferProfiles objectAtIndex:i] valueForKey:@"id"]];
            
            BOOL avatarExists = [[NSFileManager defaultManager] fileExistsAtPath:imagePath];
            if(!avatarExists){
                [bufferCache addAvatartoCacheforProfile:[[self.bufferProfiles objectAtIndex:i] valueForKey:@"id"] fromURL:avatar];
            }
            
            if([[[[self.bufferProfiles objectAtIndex:i] valueForKey:@"default"] stringValue] isEqualToString:@"1"]){
                [self.selectedProfiles addObject:[[self.bufferProfiles objectAtIndex:i] valueForKey:@"id"]];
                [self.selectedProfilesIndexes addObject:[NSString stringWithFormat:@"%d", i]];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.bufferProfileSelectionTable reloadData];
            bufferProfileCountLabel.text = [NSString stringWithFormat:@"%d", [self.selectedProfiles count]];
            [self updateAvatarStack];
            [self detectCharacterLimit];
        });
    }
}


#pragma mark - Shorten Links

// Shorten Links
-(void)shortenLinks {
    TwitterTextEntity *entity = [[TwitterText URLsInText:bufferTextCopy] objectAtIndex:0];
    NSRange r = entity.range;
    NSString *link = [bufferTextView.text substringWithRange:r];
    
    self.bufferUnshortenedLink = link;
    
    bufferTextView.text = [bufferTextView.text stringByReplacingOccurrencesOfString:link withString:@"http://buff.ly/...."];
    
    ShortenLinkService *service = [[ShortenLinkService alloc] init];
    [service shortenLink:link withSender:self];
}

-(void)replaceShortenedURL:(NSMutableDictionary *)shortened_url {
    NSString *shortened = [NSString stringWithFormat:@"%@", [shortened_url valueForKey:@"shortened"]];
    NSRange selectedRange = bufferTextView.selectedRange;
    BOOL rangeAtEnd = (selectedRange.location == bufferTextView.text.length);
    
    bufferTextView.text = [bufferTextView.text stringByReplacingOccurrencesOfString:@"http://buff.ly/...." withString:shortened];
    
    if(rangeAtEnd){
        bufferTextView.selectedRange = NSMakeRange(bufferTextView.text.length, 0);
    } else {
        bufferTextView.selectedRange = selectedRange;
    }
}

-(void)shortenLinksFailed {
    NSRange selectedRange = bufferTextView.selectedRange;
    bufferTextView.text = [bufferTextView.text stringByReplacingOccurrencesOfString:@"http://buff.ly/...." withString:self.bufferUnshortenedLink];
    bufferTextView.selectedRange = selectedRange;
}



// Profile Selection Table
#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 62;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return self.bufferProfiles.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"ProfileCell";
    
    ProfileCell *profile_cell = (ProfileCell*) [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    BufferAvatarView *avatarView;
    
    if (profile_cell == nil) {
        profile_cell = [[ProfileCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        avatarView = [[BufferAvatarView alloc] initWithFrame:CGRectMake(12, 10, 40, 40)];
        [avatarView setTag:123];
    } else {
        avatarView = (BufferAvatarView *)[profile_cell viewWithTag:123];
    }
    
    NSMutableArray* obj = [self.bufferProfiles objectAtIndex:indexPath.row];
    [profile_cell setBufferProfile:obj];
    [avatarView setBufferProfile:obj];
    
    if([self.selectedProfiles indexOfObject:[obj valueForKey:@"id"]] != NSNotFound){
        [profile_cell setState:@"selected"];
    } else {
        [profile_cell setState:@""];
    }
    
    profile_cell.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", [obj valueForKey:@"service_username"], [obj valueForKey:@"service"]];
    
    [profile_cell addSubview:avatarView];
    
    avatarView = nil;
    
    return profile_cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self toggleAccountWithIndex:[NSString stringWithFormat:@"%d", indexPath.row]];
    
}

#pragma mark - Account Selection
-(void)toggleAccountWithIndex:(NSString *)index {
    if([self.selectedProfilesIndexes indexOfObject:index] != NSNotFound){
        [self.selectedProfilesIndexes removeObjectAtIndex:[self.selectedProfilesIndexes indexOfObject:index]];
    } else {
        [self.selectedProfilesIndexes addObject:index];
    }
    
    NSString *profileID = [[self.bufferProfiles objectAtIndex:(NSInteger)[index intValue]] valueForKey:@"id"];
    
    if([self.selectedProfiles indexOfObject:profileID] != NSNotFound){
        [self.selectedProfiles removeObjectAtIndex:[self.selectedProfiles indexOfObject:profileID]];
    } else {
        [self.selectedProfiles addObject:profileID];
    }
    
    bufferProfileCountLabel.text = [NSString stringWithFormat:@"%d", [self.selectedProfiles count]];
    
    [self performSelectorOnMainThread:@selector(updateAvatarStack) withObject:nil waitUntilDone:NO];
    [self performSelectorOnMainThread:@selector(detectCharacterLimit) withObject:nil waitUntilDone:NO];
    [self.bufferProfileSelectionTable reloadData];
}

-(void)updateAvatarStack {
    [self rotateImage:avatar2Container duration:0.2 curve:0 degrees:0];
    [self rotateImage:avatar3Container duration:0.2 curve:0 degrees:0];
    
    if([self.selectedProfiles count] == 0){
        [avatarView1 setBufferProfile:nil];
        
        [UIView animateWithDuration:1 animations:^{
            avatarView1.alpha = 0;
            avatarView2.alpha = 0;
            avatarView3.alpha = 0;
        }];
        
        [avatarView2 setBufferProfile:nil];
        [avatarView3 setBufferProfile:nil];
        
    } else if([self.selectedProfiles count] == 1){
        [avatarView1 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:0] intValue]]];
        
        [UIView animateWithDuration:0.3 animations:^{
            avatarView1.alpha = 1;
            avatarView2.alpha = 0;
            avatarView3.alpha = 0;
        } completion:^(BOOL finished) {
            [avatarView2 setBufferProfile:nil];
            [avatarView3 setBufferProfile:nil];
        }];
    } else if([self.selectedProfiles count] == 2){
        [avatarView1 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:0] intValue]]];
        [avatarView2 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:1] intValue]]];
        
        [UIView animateWithDuration:0.3 animations:^{
            avatarView1.alpha = 1;
            avatarView2.alpha = 1;
            avatarView3.alpha = 0;
        } completion:^(BOOL finished) {
            [avatarView3 setBufferProfile:nil];
        }];
        
        [self rotateImage:avatar2Container duration:0.6 curve:0 degrees:15];
        
    } else if([self.selectedProfiles count] > 2){
        [avatarView1 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:0] intValue]]];
        [avatarView2 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:1] intValue]]];
        [avatarView3 setBufferProfile:[self.bufferProfiles objectAtIndex:(NSInteger)[[self.selectedProfilesIndexes objectAtIndex:2] intValue]]];
        
        [UIView animateWithDuration:0.6 animations:^{
            avatarView1.alpha = 1;
            avatarView2.alpha = 1;
            avatarView3.alpha = 1;
        }];
        
        [self rotateImage:avatar2Container duration:0.6 curve:0 degrees:15];
        [self rotateImage:avatar3Container duration:0.6 curve:0 degrees:-10];
    }
}

// This is defined in Math.h
#define M_PI   3.14159265358979323846264338327950288   /* pi */

// Our conversion definition
#define DEGREES_TO_RADIANS(angle) (angle / 180.0 * M_PI)

- (void)rotateImage:(UIView *)view duration:(NSTimeInterval)duration curve:(int)curve degrees:(CGFloat)degrees {
    // Setup the animation
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    [UIView setAnimationBeginsFromCurrentState:YES];
    
    // The transform matrix
    CGAffineTransform transform = CGAffineTransformMakeRotation(DEGREES_TO_RADIANS(degrees));
    view.transform = transform;
    
    // Commit the changes
    [UIView commitAnimations];
}


#pragma mark - Character Counts
-(void)detectCharacterLimit {
    // Loop through the character counts from smallest to biggest checking whether a profile of that type is selected.
    for (NSString *service in self.bufferCharacterCountOrder) {
                
        if([self isServiceAccountActive:service]){
                        
            if([service isEqualToString:@"Twitter"]){
                bufferCharLabel.text = [NSString stringWithFormat:@"%d", [TwitterText remainingCharacterCount:bufferTextView.text]];
                [bufferCharLabel setHidden:NO];
            } else {
                bufferCharLabel.text = [NSString stringWithFormat:@"%d", [self remainingCharacterCountForService:service]];
                if([self remainingCharacterCountForService:service] <= 140){
                    [bufferCharLabel setHidden:NO];
                } else {
                    [bufferCharLabel setHidden:YES];
                }
            }
            
            // Set the smallest active account type as active character count
            self.bufferActiveCharacterCount = service;
            
            return;
        }
    }
    
    [bufferCharLabel setHidden:YES];
}

-(BOOL)isServiceAccountActive:(NSString *)serviceType {
    for (NSString * profile_id in self.selectedProfiles) {
        for (NSMutableArray* profile in self.bufferProfiles) {
            if([[profile valueForKey:@"id"] isEqualToString:profile_id]){
                if([[profile valueForKey:@"formatted_service"] isEqualToString:serviceType]){
                    return TRUE;
                }
            }
        }
    }
    return FALSE;
}

-(int)remainingCharacterCountForService:(NSString *)service {
    int service_character_limit = [[self.bufferCharacterCount valueForKey:service] intValue];
    
    int count = service_character_limit - bufferTextView.text.length;
    return count;
}

- (void)textViewDidChange:(UITextView *)textView {
    if([self.bufferActiveCharacterCount isEqualToString:@"Twitter"]){
        bufferCharLabel.text = [NSString stringWithFormat:@"%d", [TwitterText remainingCharacterCount:bufferTextView.text]];
    } else {
        bufferCharLabel.text = [NSString stringWithFormat:@"%d", [self remainingCharacterCountForService:self.bufferActiveCharacterCount]];
        if([self remainingCharacterCountForService:self.bufferActiveCharacterCount] <= 140){
            [bufferCharLabel setHidden:NO];
        } else {
            [bufferCharLabel setHidden:YES];
        }
    }
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    [self toggleProfileSelection];
}

- (void)scrollViewDidScroll:(id)scrollView {
    if(scrollView == bufferTextView){
        [bufferTextViewContainer setContentOffset:bufferTextView.contentOffset];
    }
}

// Add to Buffer
-(void)addUpdate {
    
    if([self.selectedProfiles count] == 0){
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"No Profiles Selected"
                                                        message: @"Select a profile to add this update to."
                                                       delegate: self
                                              cancelButtonTitle: @"OK"
                                              otherButtonTitles: nil];
        [alert show];
    } else if([bufferTextView.text length] == 0){
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"No update content"
                                                        message: @"Please add some content to this update."
                                                       delegate: self
                                              cancelButtonTitle: @"OK"
                                              otherButtonTitles: nil];
        [alert show];
    } else if([self.bufferActiveCharacterCount isEqualToString:@"Twitter"] && [TwitterText remainingCharacterCount:bufferTextView.text] < 0){
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Update too long"
                                                        message: @"Please reduce the number of characters."
                                                       delegate: self
                                              cancelButtonTitle: @"OK"
                                              otherButtonTitles: nil];
        [alert show];
    } else if(![self.bufferActiveCharacterCount isEqualToString:@"Twitter"] && [self remainingCharacterCountForService:self.bufferActiveCharacterCount] < 0){
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"Update too long"
                                                        message: @"Please reduce the number of characters."
                                                       delegate: self
                                              cancelButtonTitle: @"OK"
                                              otherButtonTitles: nil];
        [alert show];
    } else {
        [bufferAddButton setHidden:YES];
        
        PostUpdateService *service = [[PostUpdateService alloc] init];
        [service postUpdate:bufferTextView.text forProfiles:self.selectedProfiles withShortening:linkShorteningEnabled withSender:self];
        
        [self.navigationController popViewControllerAnimated:YES];
    }
}

-(void)updatePosted {
    if([bufferUIActivityDelegate respondsToSelector: @selector(activityDidFinish:)]){
        [bufferUIActivityDelegate activityDidFinish:YES];
    }
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

-(void)errorAddingUpdate:(NSString *)error {
    bufferSheetErrorLabel.text = error;
    
    [bufferAddButton setHidden:NO];
    
    [bufferSheetBackground addSubview:bufferSheetErrorView];
}


#pragma mark - Button Actions

-(IBAction)toggleProfileSelection:(id)sender {
    [self toggleProfileSelection];
}

-(void)toggleProfileSelection {    
    if(profileSelectionActive){
        [bufferTextView becomeFirstResponder];
        profileSelectionActive = NO;
    } else {
        [bufferTextView resignFirstResponder];
        profileSelectionActive = YES;
    }
}

-(IBAction)errorDismissed:(id)sender {
	[bufferSheetErrorView removeFromSuperview];
}

-(IBAction)addToBuffer:(id)sender {
    [self addUpdate];
}

-(IBAction)cancel:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
    if([bufferUIActivityDelegate respondsToSelector: @selector(activityDidFinish:)]){
        [bufferUIActivityDelegate activityDidFinish:YES];
    }
}

#pragma mark - Orientation Changes

-(void)viewWillLayoutSubviews {
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    [self rotateViewWithOrientation:orientation];
    [self.bufferProfileSelectionTable reloadData];
}

-(void)rotateViewWithOrientation:(UIInterfaceOrientation)orientation {
    bufferSheetContainer.frame = CGRectMake(0, 0, self.view.frame.size.width, 245);
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        // Need to get the keyboard size programatically and set the correct height of the profile selection view ideally.
        if(UIInterfaceOrientationIsPortrait(orientation)){
            bufferSheetBackground.frame = CGRectMake((self.view.frame.size.width/2) - 250, 25,  500, 190);
            bufferProfileSelectionView.frame = CGRectMake(0, self.view.frame.size.height - 250, self.view.frame.size.width, 250);
        }
        if(UIInterfaceOrientationIsLandscape(orientation)){
            bufferSheetBackground.frame = CGRectMake((self.view.frame.size.width/2) - 250, 10, 500, 190);
            bufferProfileSelectionView.frame = CGRectMake(0, self.view.frame.size.height - 250, self.view.frame.size.width, 250);
        }
    } else {
        if(UIInterfaceOrientationIsPortrait(orientation)){
            avatar1Container.frame = CGRectMake(11, 49, 45, 45);
            avatar2Container.frame = CGRectMake(13, 48, 45, 45);
            avatar3Container.frame = CGRectMake(9, 48, 45, 45);
            
            bufferSheetBackground.frame = CGRectMake(9, 28, 302, 190);
            bufferProfileSelectionView.frame = CGRectMake(0, self.view.frame.size.height - 215, 320, 215);
        }
        if(UIInterfaceOrientationIsLandscape(orientation)){
            avatar1Container.frame = CGRectMake(16, 43, 45, 45);
            avatar2Container.frame = CGRectMake(18, 43, 45, 45);
            avatar3Container.frame = CGRectMake(14, 43, 45, 45);
            
            bufferSheetBackground.frame = CGRectMake((self.view.frame.size.width/2) - 232, 5, 480 - 16, 128);
            bufferProfileSelectionView.frame = CGRectMake(0, self.view.frame.size.height - 162, self.view.frame.size.width, 162);
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
