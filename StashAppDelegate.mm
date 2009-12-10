/* 
 * Stash:  A Personal Finance app for OS X.
 * Copyright (C) 2009 Peter Pearson
 * You can view the complete license in the Licence.txt file in the root
 * of the source tree.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 */

#import "StashAppDelegate.h"
#import "IndexItem.h"
#include "storage.h"
#import "AccountInfoController.h"
#include "analysis.h"

@implementation StashAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{	
	m_HasFinishedLoading = true;
	
	if (m_sPendingOpenFile != nil)
	{
		[self application:nil openFile:m_sPendingOpenFile];
	}
	else
	{
		if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GeneralOpenLastFile"] == YES)
		{
			NSArray *aDocuments = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
			
			if ([aDocuments count] > 0)
			{
				NSURL *url = [aDocuments objectAtIndex:0];
				
				[self application:nil openFile:[url path]];
				
				return;
			}
		}
		
		[self buildIndexTree];
	
		[window makeKeyAndOrderFront:self];
	}
	
	[self calculateAndShowScheduled];
}

- (id)init
{
	self = [super init];
	if (self)
	{
		prefController = [[PreferencesController alloc] init];
		
		m_HasFinishedLoading = false;
		m_sPendingOpenFile = nil;
		
		[NSApp setDelegate: self];
	}
	
	return self;
}

- (void)dealloc
{
	[prefController release];
	
	NSNotificationCenter *nc;
	nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:self];
	
	[super dealloc];
}

+ (void)initialize
{
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"GeneralOpenLastFile"];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:@"GeneralScrollToLatest"];
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"GeneralCreateBackupOnSave"];
		
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

- (void)awakeFromNib
{
	m_bEditing = false;	
	m_SelectedTransaction = 0;
	
	nShowTransactionsType = LAST_30DAYS;
	
	[window setDelegate:self];
	
	[indexView setFrameSize:[indexViewPlaceholder frame].size];
	[indexViewPlaceholder addSubview:indexView];
	
	[vTransactionsView setFrameSize:[contentViewPlaceholder frame].size];
	
	[contentViewPlaceholder addSubview:vTransactionsView];
	contentView = vTransactionsView;
	
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	
	float fPosX = [[defs objectForKey:@"MainWndPosX"] floatValue];
	float fPosY = [[defs objectForKey:@"MainWndPosY"] floatValue];
	float fWidth = [[defs objectForKey:@"MainWndWidth"] floatValue];
	float fHeight = [[defs objectForKey:@"MainWndHeight"] floatValue];
	
	if (fPosX >= 0.0 && fPosY >= 0.0 && fWidth > 0.0 && fHeight > 0.0)
	{
		NSScreen *mainScreen = [NSScreen mainScreen];
		NSRect screenRect = [mainScreen frame];
		
		if (fWidth <= screenRect.size.width && fHeight <= screenRect.size.height)
		{
			NSRect windowRect = NSMakeRect(fPosX, fPosY, fWidth, fHeight);
			
			[window setFrame:windowRect display:YES animate:NO];
		}
	}
	
	m_aTransactionItems = [[NSMutableArray alloc] init];
	m_aPayeeItems = [[NSMutableArray alloc] init];
	m_aCategoryItems = [[NSMutableArray alloc] init];
	m_aScheduledTransactions = [[NSMutableArray alloc] init];
	
	// Load Transactions view OutlineView column sizes
	int nCol = 0;
	for (NSTableColumn *tc in [transactionsTableView tableColumns])
	{
		NSString *sColKey = [NSString stringWithFormat:@"TransactionColWidth%i", nCol++];
		float fWidth = [[defs objectForKey:sColKey] floatValue];
		
		if (fWidth > 0.0)
		{
			[tc setWidth:fWidth];
		}
	}
	
	NSDate *date1 = [NSDate date];
	[transactionsDateCntl setDateValue:date1];
	[scheduledDateCntl setDateValue:date1];
	
	[transactionsType removeAllItems];
	
	[transactionsType addItemWithTitle:@"None"];
	[transactionsType addItemWithTitle:@"Deposit"];
	[transactionsType addItemWithTitle:@"Withdrawal"];
	[transactionsType addItemWithTitle:@"Transfer"];
	[transactionsType addItemWithTitle:@"Standing Order"];
	[transactionsType addItemWithTitle:@"Direct Debit"];
	[transactionsType addItemWithTitle:@"Point Of Sale"];
	[transactionsType addItemWithTitle:@"Charge"];
	[transactionsType addItemWithTitle:@"ATM"];
	
	[scheduledType removeAllItems];
	
	[scheduledType addItemWithTitle:@"None"];
	[scheduledType addItemWithTitle:@"Deposit"];
	[scheduledType addItemWithTitle:@"Withdrawal"];
	[scheduledType addItemWithTitle:@"Transfer"];
	[scheduledType addItemWithTitle:@"Standing Order"];
	[scheduledType addItemWithTitle:@"Direct Debit"];
	[scheduledType addItemWithTitle:@"Point Of Sale"];
	[scheduledType addItemWithTitle:@"Charge"];
	[scheduledType addItemWithTitle:@"ATM"];
	
	[scheduledFrequency removeAllItems];
	
	[scheduledFrequency addItemWithTitle:@"Weekly"];
	[scheduledFrequency addItemWithTitle:@"Two Weeks"];
	[scheduledFrequency addItemWithTitle:@"Four Weeks"];
	[scheduledFrequency addItemWithTitle:@"Monthly"];
	[scheduledFrequency addItemWithTitle:@"Two Months"];
	[scheduledFrequency addItemWithTitle:@"Quarterly"];
	[scheduledFrequency addItemWithTitle:@"Annually"];
	
	[graphType removeAllItems];
	
	[graphType addItemWithTitle:@"Expense Categories"];
	[graphType addItemWithTitle:@"Expense Payees"];
	[graphType addItemWithTitle:@"Desposit Categories"];
	[graphType addItemWithTitle:@"Deposit Payees"];
	
	[transactionsType selectItemAtIndex:0];
	
	[addTransaction setToolTip:@"Add Transaction"];
	[deleteTransaction setToolTip:@"Delete Transaction"];
	[splitTransaction setToolTip:@"Split Transaction"];
	[moveDown setToolTip:@"Move Down"];
	[moveUp setToolTip:@"Move Up"];
	[refresh setToolTip:@"Refresh"];
	
	[deleteTransaction setEnabled:NO];
	[splitTransaction setEnabled:NO];
	[moveUp setEnabled:NO];
	[moveDown setEnabled:NO];
	
	[deleteScheduled setEnabled:NO];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(TransactionSelectionDidChange:) name:NSOutlineViewSelectionDidChangeNotification object:transactionsTableView];
	[nc addObserver:self selector:@selector(ScheduledSelectionDidChange:) name:NSTableViewSelectionDidChangeNotification object:scheduledTransactionsTableView];
	
	[transactionsTableView setDelegate:self];
	[transactionsTableView setAutoresizesOutlineColumn:NO];
	[payeesTableView setDelegate:self];	
	[categoriesTableView setDelegate:self];
	[scheduledTransactionsTableView setDelegate:self];
}

- (void)buildIndexTree
{
	[indexBar clearAllItems];
	
	[indexBar addSection:@"accounts" title:@"ACCOUNTS"];
	
	std::vector<Account>::iterator it = m_Document.AccountBegin();
	int nAccount = 0;
	
	for (; it != m_Document.AccountEnd(); ++it, nAccount++)
	{
		std::string strName = it->getName();
		NSString *sName = [[NSString alloc] initWithUTF8String:strName.c_str()];
		
		NSString *sAccountKey = [NSString stringWithFormat:@"a%d", nAccount];

		[indexBar addItem:@"accounts" key:sAccountKey title:sName item:nAccount action:@selector(accountSelected:) target:self type:1 rename:@selector(accountRenamed:) renameTarget:self];
		
		[sName release];
	}
	
	[indexBar addSection:@"manage" title:@"MANAGE"];
	[indexBar addItem:@"manage" key:@"payees" title:@"Payees" item:0 action:@selector(payeesSelected:) target:self type:2 rename:nil renameTarget:nil];
	[indexBar addItem:@"manage" key:@"categories" title:@"Categories" item:0 action:@selector(categoriesSelected:) target:self type:2 rename:nil renameTarget:nil];
	[indexBar addItem:@"manage" key:@"scheduled" title:@"Scheduled" item:0 action:@selector(scheduledSelected:) target:self type:2 rename:nil renameTarget:nil];
	
	[indexBar addSection:@"graphs" title:@"GRAPHS"];
	
	std::vector<Graph>::iterator itGraph = m_Document.GraphBegin();
	int nGraph = 0;
	
	for (; itGraph != m_Document.GraphEnd(); ++itGraph, nGraph++)
	{
		std::string strName = itGraph->getName();
		NSString *sName = [[NSString alloc] initWithUTF8String:strName.c_str()];
		
		NSString *sGraphKey = [NSString stringWithFormat:@"g%d", nGraph];
		
		[indexBar addItem:@"graphs" key:sGraphKey title:sName item:nGraph action:@selector(graphSelected:) target:self type:3 rename:@selector(graphRenamed:) renameTarget:self];
		
		[sName release];
	}
	
	m_pAccount = 0;
	m_pGraph = 0;
	
	m_SelectedTransaction = 0; 
	m_bEditing = false;
	
	[indexBar reloadData];
	
	[indexBar expandSection:@"accounts"];
	[indexBar expandSection:@"manage"];
	[indexBar expandSection:@"graphs"];
	
	if (nAccount > 0)
	{
		// automatically select the first account
		[indexBar selectItem:@"a0"];
	}
}

- (void)accountSelected:(id)sender
{
	m_bEditing = false;
	
	int nAccount = [sender getItemIndex];
		
	m_pAccount = m_Document.getAccountPtr(nAccount);			
	m_SelectedTransaction = 0;
	
	[vTransactionsView setFrameSize:[contentViewPlaceholder frame].size];
	[contentViewPlaceholder replaceSubview:contentView with:vTransactionsView];
	contentView = vTransactionsView;
	
	[transactionsPayee setStringValue:@""];
	[transactionsDescription setStringValue:@""];
	[transactionsCategory setStringValue:@""];
	[transactionsAmount setStringValue:@""];
	[transactionsType selectItemAtIndex:0];
	[transactionsReconciled setState:NSOffState];
	
	[transactionsTableView deselectAll:self];
	
	[self buildTransactionsTree];
	[self refreshLibraryItems];
	[self updateUI];	
}

- (void)payeesSelected:(id)sender
{
	m_bEditing = false;
	
	[vPayeesView setFrameSize:[contentViewPlaceholder frame].size];
	[contentViewPlaceholder replaceSubview:contentView with:vPayeesView];
	contentView = vPayeesView;
	
	[self buildPayeesList];
}

- (void)categoriesSelected:(id)sender
{
	m_bEditing = false;
	
	[vCategoriesView setFrameSize:[contentViewPlaceholder frame].size];
	[contentViewPlaceholder replaceSubview:contentView with:vCategoriesView];
	contentView = vCategoriesView;
	
	[self buildCategoriesList];
}

- (void)scheduledSelected:(id)sender
{
	m_bEditing = false;
	
	m_pAccount = 0;
	
	[vScheduledView setFrameSize:[contentViewPlaceholder frame].size];
	[contentViewPlaceholder replaceSubview:contentView with:vScheduledView];
	contentView = vScheduledView;
	
	// Update the list of Accounts
	
	[scheduledAccount removeAllItems];
	
	std::vector<Account>::iterator it = m_Document.AccountBegin();
	
	for (; it != m_Document.AccountEnd(); ++it)
	{
		std::string strName = it->getName();
		NSString *sName = [[NSString alloc] initWithUTF8String:strName.c_str()];
		[scheduledAccount addItemWithTitle:sName];
		
		[sName release];
	}
	
	[scheduledTransactionsTableView deselectAll:self];
	
	[self refreshLibraryItems];
	
	[self buildSchedTransList];
}

- (void)graphSelected:(id)sender
{
	m_bEditing = false;
	
	m_pAccount = 0;
	
	int nGraph = [sender getItemIndex];
	
	m_pGraph = m_Document.getGraphPtr(nGraph);
	
	[vGraphView setFrameSize:[contentViewPlaceholder frame].size];
	[contentViewPlaceholder replaceSubview:contentView with:vGraphView];
	contentView = vGraphView;
	
	// Update the list of Accounts
	
	[graphAccount removeAllItems];
	
	std::vector<Account>::iterator it = m_Document.AccountBegin();
	
	for (; it != m_Document.AccountEnd(); ++it)
	{
		std::string strName = it->getName();
		NSString *sName = [[NSString alloc] initWithUTF8String:strName.c_str()];
		[graphAccount addItemWithTitle:sName];
		
		[sName release];
	}
	
	int nAccount = m_pGraph->getAccount();
	
	[graphAccount selectItemAtIndex:nAccount];
	
	NSDate *nsStartDate = convertToNSDate(const_cast<Date&>(m_pGraph->getStartDate1()));
	[graphStartDateCntrl setDateValue:nsStartDate];
	
	NSDate *nsEndDate = convertToNSDate(const_cast<Date&>(m_pGraph->getEndDate1()));
	[graphEndDateCntrl setDateValue:nsEndDate];
	
	GraphType eType = m_pGraph->getType();
	
	[graphType selectItemAtIndex:eType];
	
	if (m_pGraph->getIgnoreTransfers())
	{
		[graphIgnoreTransfers setState:NSOnState];
	}
	else
	{
		[graphIgnoreTransfers setState:NSOffState];
	}
	
	// for some reason, the above sets/selects don't always update the controls properly
	[graphAccount setNeedsDisplay:YES];
	[graphStartDateCntrl setNeedsDisplay:YES];
	[graphEndDateCntrl setNeedsDisplay:YES];
	
	[self buildGraph];
}

// handle renames in the IndexBar

- (void)accountRenamed:(id)sender
{
	int nAccount = [sender getItemIndex];
	
	m_pAccount = m_Document.getAccountPtr(nAccount);
	
	NSString *title = [sender title];
	
	std::string strName = [title cStringUsingEncoding:NSASCIIStringEncoding];
	
	m_pAccount->setName(strName);
	
	m_UnsavedChanges = true;
	
	[indexBar reloadData];
	[indexBar setNeedsDisplay:YES];
}

- (void)graphRenamed:(id)sender
{
	int nGraph = [sender getItemIndex];
	
	m_pGraph = m_Document.getGraphPtr(nGraph);
	
	NSString *title = [sender title];
	
	std::string strName = [title cStringUsingEncoding:NSASCIIStringEncoding];
	
	m_pGraph->setName(strName);
	
	m_UnsavedChanges = true;
	
	[indexBar reloadData];
}

- (void)buildTransactionsTree
{
	[m_aTransactionItems removeAllObjects];
	
	fixed localBalance = 0.0;
	
	if (!m_pAccount)
	{
		[transactionsTableView reloadData];
		return;
	}
	
	if (m_pAccount->getTransactionCount() == 0)
		return;
	
	std::vector<Transaction>::iterator it = m_pAccount->begin();
	int nTransaction = 0;
	m_nTransactionOffset = 0;
	
	if (nShowTransactionsType == LAST_30DAYS)
	{
		Date dateNow;
		dateNow.Now();
		
		dateNow.DecrementDays(30);
		
		std::vector<Transaction>::iterator itTemp = m_pAccount->begin();
		
		for (; itTemp != m_pAccount->end(); ++itTemp)
		{
			if ((*itTemp).Date1() >= dateNow)
				break;
			
			localBalance += (*itTemp).Amount();
			nTransaction++;
		}
		
		it = itTemp;
		
		m_nTransactionOffset = nTransaction;
	}
	else if (nShowTransactionsType == ALL_THIS_YEAR)
	{
		Date dateNow;
		dateNow.Now();
		
		Date dateComp(1, 1, dateNow.Year());
		
		std::vector<Transaction>::iterator itTemp = m_pAccount->begin();
		
		for (; itTemp != m_pAccount->end(); ++itTemp)
		{
			if ((*itTemp).Date1() >= dateComp)
				break;
			
			localBalance += (*itTemp).Amount();
			nTransaction++;
		}
		
		it = itTemp;
		
		m_nTransactionOffset = nTransaction;
	}
	
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	for (; it != m_pAccount->end(); ++it, nTransaction++)
	{
		TransactionItem *newTransaction = [[TransactionItem alloc] init];
		
		std::string strTPayee = it->Payee();
		NSString *sTPayee = [[NSString alloc] initWithUTF8String:strTPayee.c_str()];
		
		std::string strTDescription = it->Description();
		NSString *sTDescription = [[NSString alloc] initWithUTF8String:strTDescription.c_str()];
		
		std::string strTCategory = it->Category();
		NSString *sTCategory = [[NSString alloc] initWithUTF8String:strTCategory.c_str()];
		
		NSNumber *nTAmount = [NSNumber numberWithDouble:it->Amount().ToDouble()];
		
		NSString *sTAmount = [[numberFormatter stringFromNumber:nTAmount] retain];
		
		NSDate *date = convertToNSDate(const_cast<Date&>(it->Date2()));
		NSString *sTDate = [[dateFormatter stringFromDate:date] retain];
		
		localBalance += it->Amount();
		
		m_aBalance.push_back(localBalance);
		
		NSNumber *nTBalance = [NSNumber numberWithDouble:localBalance.ToDouble()];
		NSString *sTBalance = [[numberFormatter stringFromNumber:nTBalance] retain];
		
		[newTransaction setTransaction:nTransaction];
		
		int recon = it->isReconciled();
		
		[newTransaction setIntValue:recon forKey:@"Reconciled"];
		[newTransaction setValue:sTDate forKey:@"Date"];
		[newTransaction setValue:sTPayee forKey:@"Payee"];
		[newTransaction setValue:sTDescription forKey:@"Description"];
		[newTransaction setValue:sTCategory forKey:@"Category"];
		[newTransaction setValue:sTAmount forKey:@"Amount"];
		[newTransaction setValue:sTBalance forKey:@"Balance"];
		
		[newTransaction setIntValue:nTransaction forKey:@"Transaction"];
		
		if (it->Split())
		{
			int nSplits = it->getSplitCount();
			
			fixed splitValue = it->Amount();
			
			for (int i = 0; i < nSplits; i++)
			{
				SplitTransaction & split = it->getSplit(i);
				
				TransactionItem *newSplit = [[TransactionItem alloc] init];
				
				std::string strSPayee = split.Payee();
				NSString *sSPayee = [[NSString alloc] initWithUTF8String:strSPayee.c_str()];
				
				std::string strSDescription = split.Description();
				NSString *sSDescription = [[NSString alloc] initWithUTF8String:strSDescription.c_str()];
				
				std::string strSCategory = split.Category();
				NSString *sSCategory = [[NSString alloc] initWithUTF8String:strSCategory.c_str()];
				
				NSNumber *nSAmount = [NSNumber numberWithDouble:split.Amount().ToDouble()];
				NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
				
				[newSplit setValue:sSPayee forKey:@"Payee"];
				[newSplit setValue:sSDescription forKey:@"Description"];
				[newSplit setValue:sSCategory forKey:@"Category"];
				[newSplit setValue:sSAmount forKey:@"Amount"];
				
				[newSplit setTransaction:nTransaction];
				[newSplit setIntValue:nTransaction forKey:@"Transaction"];
				
				[newSplit setSplitTransaction:i];
				[newSplit setIntValue:i forKey:@"Split"];
				
				splitValue -= split.Amount();
				
				[newTransaction addChild:newSplit];
				
				[sSPayee release];
				[sSDescription release];
				[sSCategory release];
				[sSAmount release];
			}
			
			// add remainder as a temp editable row
			
			if (!splitValue.IsZero())
			{
				TransactionItem *newSplit = [[TransactionItem alloc] init];
				
				NSNumber *nSAmount = [NSNumber numberWithDouble:splitValue.ToDouble()];
				NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
				
				[newSplit setValue:@"Split Value" forKey:@"Description"];
				[newSplit setValue:@"Split Value" forKey:@"Payee"];
				[newSplit setValue:sSAmount forKey:@"Amount"];
				
				[newSplit setTransaction:nTransaction];
				[newSplit setIntValue:nTransaction forKey:@"Transaction"];
				
				[newSplit setSplitTransaction:-2];
				[newSplit setIntValue:-2 forKey:@"Split"];
				
				[newTransaction addChild:newSplit];
				[sSAmount release];
			}
		}		
		
		[m_aTransactionItems addObject:newTransaction];
		[sTPayee release];
		[sTDescription release];
		[sTCategory release];
		[sTAmount release];
		[sTDate release];
		[sTBalance release];
	}
	
	[dateFormatter release];
	[numberFormatter release];
	
	[transactionsTableView reloadData];
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GeneralScrollToLatest"] == YES)
	{
		int latest = [transactionsTableView numberOfRows];
		[transactionsTableView scrollRowToVisible:latest - 1];
	}
}

- (void)buildPayeesList
{
	[m_aPayeeItems removeAllObjects];
		
	std::set<std::string>::iterator it = m_Document.PayeeBegin();
	
	for (; it != m_Document.PayeeEnd(); ++it)
	{
		std::string strPayee = (*it);
		NSString *sPayee = [[NSString alloc] initWithUTF8String:strPayee.c_str()];
			
		[m_aPayeeItems addObject:sPayee];
		[sPayee release];
	}
	
	[payeesTableView reloadData];	
}

- (void)buildCategoriesList
{
	[m_aCategoryItems removeAllObjects];
	
	std::set<std::string>::iterator it = m_Document.CategoryBegin();
	
	for (; it != m_Document.CategoryEnd(); ++it)
	{
		std::string strCategory = (*it);
		NSString *sCategory = [[NSString alloc] initWithUTF8String:strCategory.c_str()];
		
		[m_aCategoryItems addObject:sCategory];
		[sCategory release];
	}
	
	[categoriesTableView reloadData];	
}

- (void)buildSchedTransList
{
	[m_aScheduledTransactions removeAllObjects];
	
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	std::vector<ScheduledTransaction>::iterator it = m_Document.SchedTransBegin();
	
	int schedTransIndex = 0;
	
	for (; it != m_Document.SchedTransEnd(); ++it, schedTransIndex++)
	{
		NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
		
		std::string strSPayee = it->getPayee();
		NSString *sSPayee = [[NSString alloc] initWithUTF8String:strSPayee.c_str()];
		
		std::string strSCategory = it->getCategory();
		NSString *sSCategory = [[NSString alloc] initWithUTF8String:strSCategory.c_str()];
		
		NSNumber *nSAmount = [NSNumber numberWithDouble:it->getAmount().ToDouble()];
		
		NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
		
		NSDate *date = convertToNSDate(const_cast<Date&>(it->getNextDate2()));
		NSString *sSDate = [[dateFormatter stringFromDate:date] retain];
		
		int nFreq = it->getFrequency();
		NSString *sFrequency = [scheduledFrequency itemTitleAtIndex:nFreq];
		
		int nAccount = it->getAccount();
		int nNumAccounts = [scheduledAccount numberOfItems];
		
		NSString *sAccount = @"";
		if (nAccount >= 0 && nAccount < nNumAccounts)
		{
			sAccount = [scheduledAccount itemTitleAtIndex:nAccount];
		}
		
		bool isEnabled = it->isEnabled();
		
		[item setValue:[NSNumber numberWithBool:isEnabled] forKey:@"enabled"];
		[item setValue:[NSNumber numberWithInt:schedTransIndex] forKey:@"index"];
		[item setValue:sSPayee forKey:@"payee"];
		[item setValue:sSCategory forKey:@"category"];
		[item setValue:sSAmount forKey:@"amount"];
		[item setValue:sSDate forKey:@"nextdate"];
		[item setValue:sFrequency forKey:@"frequency"];
		[item setValue:sAccount forKey:@"account"];
		
		[m_aScheduledTransactions addObject:item];
	}
	
	[dateFormatter release];
	[numberFormatter release];
	
	[scheduledTransactionsTableView reloadData];
}

- (void)buildGraph
{
	if (!m_pGraph)
		return;
	
	int nAccount = m_pGraph->getAccount();
	
	if (nAccount < 0)
		return;
	
	Account *pAccount = m_Document.getAccountPtr(nAccount);
	
	GraphType eType = m_pGraph->getType();
		
	Date startDate = m_pGraph->getStartDate();
	Date endDate = m_pGraph->getEndDate();
	
	bool bIgnoreTransfers = m_pGraph->getIgnoreTransfers();
	
	std::vector<GraphValue> aGraphItems;
	
	fixed overallTotal = 0.0;
	
	if (eType == ExpenseCategories)
		buildItemsForExpenseCategories(pAccount, aGraphItems, startDate, endDate, overallTotal, bIgnoreTransfers);
	else if (eType == ExpensePayees)
		buildItemsForExpensePayees(pAccount, aGraphItems, startDate, endDate, overallTotal, bIgnoreTransfers);
	else if (eType == DepositCategories)
		buildItemsForDepositCategories(pAccount, aGraphItems, startDate, endDate, overallTotal, bIgnoreTransfers);
	else if (eType == DepositPayees)
		buildItemsForDepositPayees(pAccount, aGraphItems, startDate, endDate, overallTotal, bIgnoreTransfers);
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	[numberFormatter setLenient:YES];
	
	NSMutableArray *aItems = [[NSMutableArray alloc] init];
	
	std::vector<GraphValue>::iterator it = aGraphItems.begin();
	
	double startAngle = 0.0;
	
	for (; it != aGraphItems.end(); ++it)
	{
		NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
		
		std::string strTitle = (*it).getTitle();
		fixed amount = (*it).getAmount();
		double angle = (*it).getAngle();
		
		NSString *sTitle = [[NSString alloc] initWithUTF8String:strTitle.c_str()];
		
		NSNumber *nSAmount = [NSNumber numberWithDouble:amount.ToDouble()];		
		NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
		
		[dict setValue:[NSNumber numberWithDouble:angle] forKey:@"angle"];
		
		[dict setValue:[NSNumber numberWithDouble:startAngle] forKey:@"startangle"];
		
		startAngle += angle;
		
		[dict setValue:[NSNumber numberWithDouble:startAngle] forKey:@"endangle"];		 
		
		[dict setValue:sTitle forKey:@"title"];
		[dict setValue:sSAmount forKey:@"amount"];
		
		[dict setValue:nSAmount forKey:@"numamount"];
				
		[aItems addObject:dict];		
	}
	
	NSNumber *nTotal = [NSNumber numberWithDouble:overallTotal.ToDouble()];
	NSString *sTotal = [[numberFormatter stringFromNumber:nTotal] retain];
	
	[numberFormatter release];
	
	[chartView setTotal:sTotal];
	[chartView setData:aItems];	
}

- (void)refreshLibraryItems
{
	[transactionsPayee removeAllItems];
	[scheduledPayee removeAllItems];
	
	std::set<std::string>::iterator it = m_Document.PayeeBegin();
	
	for (; it != m_Document.PayeeEnd(); ++it)
	{
		NSString *sPayee = [[NSString alloc] initWithUTF8String:(*it).c_str()];
		
		[transactionsPayee addItemWithObjectValue:sPayee];
		[scheduledPayee addItemWithObjectValue:sPayee];
	}
	
	[transactionsCategory removeAllItems];
	[scheduledCategory removeAllItems];
	
	std::set<std::string>::iterator itCat = m_Document.CategoryBegin();
	
	for (; itCat != m_Document.CategoryEnd(); ++itCat)
	{
		NSString *sCategory = [[NSString alloc] initWithUTF8String:(*itCat).c_str()];
		
		[transactionsCategory addItemWithObjectValue:sCategory];
		[scheduledCategory addItemWithObjectValue:sCategory];
	}
}

- (void)updateUI
{
	if (!m_pAccount)
		return;
	
}

- (IBAction)AddAccount:(id)sender
{
	AddAccountController *addAccountController = [[AddAccountController alloc] initWnd:self];
	[addAccountController showWindow:self];
}

- (void)addAccountConfirmed:(AddAccountController *)addAccountController
{
	NSString *sAccountName = [addAccountController accountName];
	NSString *sStartingBalance = [addAccountController startingBalance];
	NSString *sInstitution = [addAccountController institution];
	NSString *sNumber = [addAccountController number];
	NSString *sNote = [addAccountController note];
	
	AccountType eType = [addAccountController accountType];
	
	std::string strName = [sAccountName cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strInstitution = [sInstitution cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strNumber = [sNumber cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strNote = [sNote cStringUsingEncoding:NSASCIIStringEncoding];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	[numberFormatter setLenient:YES];
	
	NSNumber *nStartingBalance = [numberFormatter numberFromString:sStartingBalance];
	
	fixed startingBalance = [nStartingBalance doubleValue];
	
	Account newAccount;
	newAccount.setName(strName);
	newAccount.setType(eType);
	newAccount.setInstitution(strInstitution);
	newAccount.setNumber(strNumber);
	newAccount.setNote(strNote);
	
	Date currentDate;
	currentDate.Now();
	Transaction newTransaction("Starting balance", "", "", startingBalance, currentDate);
	newTransaction.setReconciled(true);
	
	newAccount.addTransaction(newTransaction);
	
	int nAccountNum = m_Document.addAccount(newAccount);
	
	NSString *sAccountKey = [NSString stringWithFormat:@"a@s", nAccountNum];
	
	[indexBar addItem:@"accounts" key:sAccountKey title:sAccountName item:nAccountNum action:@selector(accountSelected:) target:self type:1 rename:@selector(accountRenamed:) renameTarget:self];
	
	[addAccountController release];
	[numberFormatter release];
	
	m_UnsavedChanges = true;
	
	[indexBar reloadData];
	
	if (nAccountNum == 0) // if first account added, select it
	{
		[indexBar selectItem:sAccountKey];
	}
}

- (IBAction)AccountInfo:(id)sender
{
	int nAccount = [indexBar getItemIndex];
	
	if (nAccount >= 0)
	{
		Account &oAccount = m_Document.getAccount(nAccount);
		
		NSString *sName = [[NSString alloc] initWithUTF8String:oAccount.getName().c_str()];
		NSString *sInstitution = [[NSString alloc] initWithUTF8String:oAccount.getInstitution().c_str()];
		NSString *sNumber = [[NSString alloc] initWithUTF8String:oAccount.getNumber().c_str()];
		NSString *sNote = [[NSString alloc] initWithUTF8String:oAccount.getNote().c_str()];
		AccountType eType = oAccount.getType();		
		
		AccountInfoController *accountInfoController = [[AccountInfoController alloc] initWnd:self withAccount:nAccount name:sName institution:sInstitution number:sNumber
																					 note:sNote type:eType];
		[accountInfoController showWindow:self];
		
		[sName release];
		[sInstitution release];
		[sNumber release];
		[sNote release];
	}	
}

- (void)updateAccountInfo:(int)account name:(NSString*)name institution:(NSString*)institution
				   number:(NSString*)number note:(NSString*)note type:(AccountType)type
{
	Account &oAccount = m_Document.getAccount(account);
	
	std::string strName = [name cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strInstitution = [institution cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strNumber = [number cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strNote = [note cStringUsingEncoding:NSASCIIStringEncoding];
		
	oAccount.setName(strName);
	oAccount.setType(type);
	oAccount.setInstitution(strInstitution);
	oAccount.setNumber(strNumber);
	oAccount.setNote(strNote);
	
	m_UnsavedChanges = true;
	
	[self buildIndexTree];
}

- (IBAction)DeleteAccount:(id)sender
{
	m_bEditing = false;
	
	int nAccount = [indexBar getItemIndex];
	
	if (nAccount >= 0)
	{
		NSString * message = @"The Account and all transactions in it will be deleted. Are you sure?";
		
		int choice = NSAlertDefaultReturn;
		
		choice = NSRunAlertPanel(@"Delete Account?", message, @"Delete", @"Cancel", nil);
		
		if (choice != NSAlertDefaultReturn)
			return;
		
		m_Document.deleteAccount(nAccount);
		
		m_Document.disabledScheduledTransactionsForAccount(nAccount);
		
		m_UnsavedChanges = true;
		
		[self buildIndexTree];
	}
}

- (IBAction)AddTransaction:(id)sender
{
	if (!m_pAccount)
		return;
	
	NSDate *ndate1 = [transactionsDateCntl dateValue];
	NSCalendarDate *CalDate = [ndate1 dateWithCalendarFormat:0 timeZone:0];
	
	int nYear = [CalDate yearOfCommonEra];
	int nMonth = [CalDate monthOfYear];
	int nDay = [CalDate dayOfMonth];
	
	Date date1(nDay, nMonth, nYear);
	
	Transaction newTransaction("", "", "", 0.0, date1);
	
	m_pAccount->addTransaction(newTransaction);
	
	[transactionsPayee setStringValue:@""];
	[transactionsDescription setStringValue:@""];
	[transactionsCategory setStringValue:@""];
	[transactionsAmount setStringValue:@""];
	[transactionsType selectItemAtIndex:0];
	[transactionsReconciled setState:NSOffState];
	
	TransactionItem *newIndex = [[TransactionItem alloc] init];
	
	std::string strPayee = newTransaction.Payee();
	NSString *sPayee = [[NSString alloc] initWithUTF8String:strPayee.c_str()];
	
	std::string strDescription = newTransaction.Description();
	NSString *sDescription = [[NSString alloc] initWithUTF8String:strDescription.c_str()];
	
	std::string strCategory = newTransaction.Category();
	NSString *sCategory = [[NSString alloc] initWithUTF8String:strCategory.c_str()];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	NSNumber *nAmount = [NSNumber numberWithDouble:newTransaction.Amount().ToDouble()];
	NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
		
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	NSString *sDate = [[dateFormatter stringFromDate:ndate1] retain];
	
	[dateFormatter release];
	
	fixed localBalance;
	
	if (!m_aBalance.empty())
	{
		
		localBalance = m_aBalance.back();
	}
	else
	{
		localBalance = m_pAccount->getBalance(true);
	}
	
	NSNumber *nBalance = [NSNumber numberWithDouble:localBalance.ToDouble()];
	NSString *sBalance = [[numberFormatter stringFromNumber:nBalance] retain];
	
	[numberFormatter release];
	
	int nTransaction = m_pAccount->getTransactionCount() - 1;
	
	[newIndex setTransaction:nTransaction];
	
	int recon = newTransaction.isReconciled();
	
	[newIndex setIntValue:recon forKey:@"Reconciled"];
	[newIndex setValue:sDate forKey:@"Date"];
	[newIndex setValue:sPayee forKey:@"Payee"];
	[newIndex setValue:sDescription forKey:@"Description"];
	[newIndex setValue:sCategory forKey:@"Category"];
	[newIndex setValue:sAmount forKey:@"Amount"];
	[newIndex setValue:sBalance forKey:@"Balance"];
	
	[newIndex setIntValue:nTransaction forKey:@"Transaction"];
	
	[m_aTransactionItems addObject:newIndex];
	[newIndex release];
	
	[transactionsTableView reloadData];
	
	NSInteger row = [transactionsTableView rowForItem:newIndex];
	
	[transactionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[transactionsTableView scrollRowToVisible:row];
	
	[window makeFirstResponder:transactionsPayee];
	
	m_UnsavedChanges = true;
	
	[self updateUI];
}

- (IBAction)DeleteTransaction:(id)sender
{
	NSIndexSet *rows = [transactionsTableView selectedRowIndexes];
	
	if ([rows count] > 0)
	{
		NSInteger row = [rows lastIndex];
		
		while (row != NSNotFound)
		{
			TransactionItem *item = [transactionsTableView itemAtRow:row];
			
			int nSplit = [item intKeyValue:@"Split"];
			int nTransaction = [item intKeyValue:@"Transaction"];
			
			if (nSplit == -1)
			{
				m_pAccount->deleteTransaction(nTransaction);
				[m_aTransactionItems removeObjectAtIndex:nTransaction - m_nTransactionOffset];
				
				[self updateBalancesFromTransactionIndex:row ];
			}
			else if (nSplit != -2)
			{
				TransactionItem *transactionItem = [m_aTransactionItems objectAtIndex:nTransaction - m_nTransactionOffset];
				Transaction &trans = m_pAccount->getTransaction(nTransaction);
				
				trans.deleteSplit(nSplit);
				[transactionItem deleteChild:nSplit];
			}
			
			row = [rows indexLessThanIndex:row];			
		}
		
		[transactionsTableView reloadData];
		
		m_UnsavedChanges = true;
		
		[self updateUI];
	}	
}

- (IBAction)SplitTransaction:(id)sender
{
	NSInteger row = [transactionsTableView selectedRow];
	
	if (row == NSNotFound)
		return;
	
	TransactionItem *item = [transactionsTableView itemAtRow:row];
	
	int nTransaction = [item intKeyValue:@"Transaction"];
	Transaction &trans = m_pAccount->getTransaction(nTransaction);
	
	fixed splitValue = trans.Amount();
	TransactionItem *newSplit = [[TransactionItem alloc] init];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	NSNumber *nAmount = [NSNumber numberWithDouble:splitValue.ToDouble()];
	NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
	
	[newSplit setValue:@"Split Value" forKey:@"Description"];
	[newSplit setValue:@"Split Value" forKey:@"Payee"];
	[newSplit setValue:sAmount forKey:@"Amount"];
	
	[newSplit setTransaction:nTransaction];
	[newSplit setIntValue:nTransaction forKey:@"Transaction"];
	
	[newSplit setSplitTransaction:-2];
	[newSplit setIntValue:-2 forKey:@"Split"];
	
	[item addChild:newSplit];
	
	[transactionsTableView reloadData];
	
	[transactionsTableView expandItem:item];
	
	row = [transactionsTableView rowForItem:newSplit];
	
	[transactionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[transactionsTableView scrollRowToVisible:row];
	
	[window makeFirstResponder:transactionsPayee];
	
	[numberFormatter release];
	
	m_UnsavedChanges = true;
}

- (IBAction)MoveUp:(id)sender
{
	if (!m_pAccount)
		return;
	
	NSIndexSet *rows = [transactionsTableView selectedRowIndexes];
	
	if ([rows count] == 1)
	{
		NSInteger row = [rows lastIndex];
		
		TransactionItem *thisItem = [transactionsTableView itemAtRow:row];
		
		int nSplit = [thisItem splitTransaction];
		
		if (nSplit >= 0)
		{
			return;
		}
		
		// Swap them over
		[self SwapTransactions:row to:row - 1];
	}
}

- (IBAction)MoveDown:(id)sender
{
	if (!m_pAccount)
		return;
	
	NSIndexSet *rows = [transactionsTableView selectedRowIndexes];
	
	if ([rows count] == 1)
	{
		NSInteger row = [rows lastIndex];
		
		TransactionItem *thisItem = [transactionsTableView itemAtRow:row];
		
		int nSplit = [thisItem splitTransaction];
		
		if (nSplit >= 0)
		{
			return;
		}
		
		// Swap them over
		[self SwapTransactions:row to:row + 1];
	}
}

- (void)SwapTransactions:(int)from to:(int)to
{
	if (from < 0 || to < 0)
		return;
	
	int maxTransactionIndex = [m_aTransactionItems count] - 1;
	
	if (from > maxTransactionIndex || to > maxTransactionIndex)
		return;
	
	int nRealFrom = from + m_nTransactionOffset;
	int nRealTo = to + m_nTransactionOffset;
	
	m_pAccount->swapTransactions(nRealFrom, nRealTo);
	[m_aTransactionItems exchangeObjectAtIndex:from withObjectAtIndex:to];
	
	// TransactionItem values are still pointing in the wrong place, so fix them....
	
	TransactionItem *fromItem = [transactionsTableView itemAtRow:from];
	TransactionItem *toItem = [transactionsTableView itemAtRow:to];
	
	[fromItem setTransaction:nRealTo];
	[fromItem setIntValue:nRealTo forKey:@"Transaction"];
	
	[toItem setTransaction:nRealFrom];
	[toItem setIntValue:nRealFrom forKey:@"Transaction"];
	
	if (from < to)
	{
		[self updateBalancesFromTransactionIndex:from];
	}
	else
	{
		[self updateBalancesFromTransactionIndex:to];
	}
		
	[transactionsTableView reloadData];
	
	[transactionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:to] byExtendingSelection:NO];
	[transactionsTableView scrollRowToVisible:to];
	
	m_UnsavedChanges = true;
}

- (void)RefreshView:(id)sender
{
	[self buildTransactionsTree];
	
	[transactionsTableView reloadData];	
}

- (void)TransactionSelectionDidChange:(NSNotification *)notification
{
	if (!m_pAccount)
		return;
	
	NSIndexSet *rows = [transactionsTableView selectedRowIndexes];
	
	if ([rows count] == 1)
	{
		[deleteTransaction setEnabled:YES];
		
		NSInteger row = [rows lastIndex];
		
		TransactionItem *item = [[transactionsTableView itemAtRow:row] retain];
		
		int nTrans = [item transaction];
		int nSplit = [item splitTransaction];
		
		Transaction *trans = NULL;
		SplitTransaction *split = NULL;
		
		if (nTrans >= 0)
			trans = &m_pAccount->getTransaction(nTrans);
		
		if (nSplit >= 0)
			split = &trans->getSplit(nSplit);
		
		m_SelectedTransaction = item;
		
		NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
		[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
		[numberFormatter setLenient:YES];
		
		if (trans && !split && nSplit != -2) // A normal transaction
		{
			[splitTransaction setEnabled:YES];
			[moveUp setEnabled:YES];
			[moveDown setEnabled:YES];
			
			m_bEditing = true;			
			
			std::string strPayee = trans->Payee();
			NSString *sPayee = [[NSString alloc] initWithUTF8String:strPayee.c_str()];
			
			std::string strDescription = trans->Description();
			NSString *sDescription = [[NSString alloc] initWithUTF8String:strDescription.c_str()];
			
			std::string strCategory = trans->Category();
			NSString *sCategory = [[NSString alloc] initWithUTF8String:strCategory.c_str()];
			
			NSNumber *nAmount = [NSNumber numberWithDouble:trans->Amount().ToDouble()];
			NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
			
			TransactionType eType = trans->Type();
			
			Date date1 = trans->Date1();
			NSDate *datetemp = convertToNSDate(date1);
			
			[transactionsReconciled setEnabled:YES];
			[transactionsType setEnabled:YES];
			
			bool bReconciled = trans->isReconciled();
			
			if (bReconciled)
			{
				[transactionsReconciled setState:NSOnState];
			}
			else
			{
				[transactionsReconciled setState:NSOffState];
			}
			
			[transactionsPayee setStringValue:sPayee];
			[transactionsDescription setStringValue:sDescription];
			[transactionsCategory setStringValue:sCategory];
			[transactionsAmount setStringValue:sAmount];
			[transactionsDateCntl setDateValue:datetemp];
			[transactionsType selectItemAtIndex:eType];
			
			[sPayee release];
			[sDescription release];
			[sCategory release];
			[sAmount release];
		}
		else if (trans && split && nSplit != -2)
		{
			[splitTransaction setEnabled:NO];
			[moveUp setEnabled:NO];
			[moveDown setEnabled:NO];
			
			m_bEditing = true;
			
			std::string strPayee = split->Payee();
			NSString *sPayee = [[NSString alloc] initWithUTF8String:strPayee.c_str()];
			
			std::string strDescription = split->Description();
			NSString *sDescription = [[NSString alloc] initWithUTF8String:strDescription.c_str()];
			
			std::string strCategory = split->Category();
			NSString *sCategory = [[NSString alloc] initWithUTF8String:strCategory.c_str()];
			
			NSNumber *nAmount = [NSNumber numberWithDouble:split->Amount().ToDouble()];
			NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
			
			[transactionsPayee setStringValue:sPayee];
			[transactionsDescription setStringValue:sDescription];
			[transactionsCategory setStringValue:sCategory];
			[transactionsAmount setStringValue:sAmount];
			[transactionsType selectItemAtIndex:0];
			
			[transactionsReconciled setEnabled:NO];
			[transactionsType setEnabled:NO];
			
			[sPayee release];
			[sDescription release];
			[sCategory release];
			[sAmount release];
		}
		else // Dummy Split
		{
			[splitTransaction setEnabled:NO];
			[moveUp setEnabled:NO];
			[moveDown setEnabled:NO];
			
			m_bEditing = true;
			
			NSString *sPayee = [item keyValue:@"Payee"];
			NSString *sDescription = [item keyValue:@"Description"];
			NSString *sAmount = [item keyValue:@"Amount"];
			
			[transactionsPayee setStringValue:sPayee];
			[transactionsDescription setStringValue:sDescription];
			[transactionsCategory setStringValue:@""];
			[transactionsAmount setStringValue:sAmount];
			[transactionsType selectItemAtIndex:0];
			
			[transactionsReconciled setEnabled:NO];
			[transactionsType setEnabled:NO];
		}
		
		[numberFormatter release];
	}
	else
	{
		[deleteTransaction setEnabled:NO];
		[splitTransaction setEnabled:NO];
		[moveUp setEnabled:NO];
		[moveDown setEnabled:NO];
		
		[transactionsPayee setStringValue:@""];
		[transactionsDescription setStringValue:@""];
		[transactionsCategory setStringValue:@""];
		[transactionsType selectItemAtIndex:0];
		[transactionsAmount setStringValue:@""];
		[transactionsReconciled setState:NSOffState];		
		
		m_SelectedTransaction = 0; 
		m_bEditing = false;		
	}
}

- (void)updateTransaction:(id)sender
{
	if (!m_bEditing || !m_SelectedTransaction)
		return;
	
	if ([[transactionsAmount stringValue] length] == 0)
	{
		[window makeFirstResponder:transactionsAmount];
		NSBeep();
		
		return;
	}
	
	NSDate *ndate1 = [transactionsDateCntl dateValue];
	NSCalendarDate *CalDate = [ndate1 dateWithCalendarFormat:0 timeZone:0];
	
	int nYear = [CalDate yearOfCommonEra];
	int nMonth = [CalDate monthOfYear];
	int nDay = [CalDate dayOfMonth];
	
	Date date1(nDay, nMonth, nYear);
		
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	NSString *sDate = [[dateFormatter stringFromDate:ndate1] retain];
	
	[dateFormatter release];
	
	std::string strPayee = [[transactionsPayee stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strDesc = [[transactionsDescription stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strCategory = [[transactionsCategory stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	[numberFormatter setLenient:YES];
	
	NSNumber *nAmount = [numberFormatter numberFromString:[transactionsAmount stringValue]];	
	fixed fAmount = [nAmount doubleValue];

	// reformat the number again, in case an abbreviation was used
	NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
	
	int nType = [transactionsType indexOfSelectedItem];
	TransactionType eType = static_cast<TransactionType>(nType);
	
	bool bReconciled = false;
	
	if ([transactionsReconciled state] == NSOnState)
		bReconciled = true;
	
	int nTrans = [m_SelectedTransaction transaction];
	int nSplit = [m_SelectedTransaction splitTransaction];
	
	Transaction *trans = NULL;
	SplitTransaction *split = NULL;
	
	if (nTrans >= 0)
		trans = &m_pAccount->getTransaction(nTrans);
	
	if (nSplit >= 0)
		split = &trans->getSplit(nSplit);
	
	if (trans && !split && nSplit != -2)
	{
		trans->setDate(date1);
		trans->setPayee(strPayee);
		trans->setDescription(strDesc);
		trans->setCategory(strCategory);
		trans->setType(eType);
		trans->setReconciled(bReconciled);
		
		fixed oldAmount = trans->Amount();
		
		if (oldAmount != fAmount)
		{
			trans->setAmount(fAmount);
			[self updateBalancesFromTransactionIndex:nTrans];
		}
		
		[m_SelectedTransaction setValue:sDate forKey:@"Date"];
		[m_SelectedTransaction setValue:[transactionsPayee stringValue] forKey:@"Payee"];
		[m_SelectedTransaction setValue:[transactionsDescription stringValue] forKey:@"Description"];
		[m_SelectedTransaction setValue:[transactionsCategory stringValue] forKey:@"Category"];
		[m_SelectedTransaction setValue:sAmount forKey:@"Amount"];
		[m_SelectedTransaction setIntValue:bReconciled forKey:@"Reconciled"];
		
		if (!strPayee.empty() && !m_Document.doesPayeeExist(strPayee))
		{
			m_Document.addPayee(strPayee);
			[transactionsPayee addItemWithObjectValue:[transactionsPayee stringValue]];
		}
		
		if (!strCategory.empty() && !m_Document.doesCategoryExist(strCategory))
		{
			m_Document.addCategory(strCategory);
			[transactionsCategory addItemWithObjectValue:[transactionsCategory stringValue]];
		}
		
		[transactionsTableView reloadData];
	}
	else
	{
		if (nSplit != -2)
		{
			split->setPayee(strPayee);
			split->setDescription(strDesc);
			split->setCategory(strCategory);
			split->setAmount(fAmount);
			
			[m_SelectedTransaction setValue:[transactionsPayee stringValue] forKey:@"Payee"];
			[m_SelectedTransaction setValue:[transactionsDescription stringValue] forKey:@"Description"];
			[m_SelectedTransaction setValue:[transactionsCategory stringValue] forKey:@"Category"];
			[m_SelectedTransaction setValue:sAmount forKey:@"Amount"];
			[m_SelectedTransaction setIntValue:bReconciled forKey:@"Reconciled"];
			
			if (!strPayee.empty() && !m_Document.doesPayeeExist(strPayee))
			{
				m_Document.addPayee(strPayee);
				[transactionsPayee addItemWithObjectValue:[transactionsPayee stringValue]];
			}
			
			if (!strCategory.empty() && !m_Document.doesCategoryExist(strCategory))
			{
				m_Document.addCategory(strCategory);
				[transactionsCategory addItemWithObjectValue:[transactionsCategory stringValue]];
			}
			
			[transactionsTableView reloadData];
		}
		else if (nSplit == -2) // Dummy value, so convert to a real split
		{
			fixed transValue = trans->Amount();			
			
			trans->addSplit(strDesc, strPayee, strCategory, fAmount);
			
			int nSplitsNumber = trans->getSplitCount() - 1;
			[m_SelectedTransaction setSplitTransaction:nSplitsNumber];
			[m_SelectedTransaction setIntValue:nSplitsNumber forKey:@"Split"];
			[m_SelectedTransaction setValue:[transactionsPayee stringValue] forKey:@"Payee"];
			[m_SelectedTransaction setValue:[transactionsDescription stringValue] forKey:@"Description"];
			[m_SelectedTransaction setValue:[transactionsCategory stringValue] forKey:@"Category"];
			[m_SelectedTransaction setValue:sAmount forKey:@"Amount"];
			
			if (!strPayee.empty() && !m_Document.doesPayeeExist(strPayee))
			{
				m_Document.addPayee(strPayee);
				[transactionsPayee addItemWithObjectValue:[transactionsPayee stringValue]];
			}
			
			if (!strCategory.empty() && !m_Document.doesCategoryExist(strCategory))
			{
				m_Document.addCategory(strCategory);
				[transactionsCategory addItemWithObjectValue:[transactionsCategory stringValue]];
			}
			
			fixed splitValue = trans->getSplitTotal();
			
			fixed diff = transValue -= splitValue;
			
			// Then add a new dummy value if needed
			
			if (!diff.IsZero())
			{
				TransactionItem *transIndex = [m_aTransactionItems objectAtIndex:nTrans - m_nTransactionOffset];
				
				TransactionItem *newSplit = [[TransactionItem alloc] init];
				
				NSNumber *nSAmount = [NSNumber numberWithDouble:diff.ToDouble()];
				NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
				
				[newSplit setValue:@"Split Value" forKey:@"Payee"];
				[newSplit setValue:@"Split Value" forKey:@"Description"];
				[newSplit setValue:sSAmount forKey:@"Amount"];
				
				[newSplit setTransaction:nTrans];
				[newSplit setIntValue:nTrans forKey:@"Transaction"];
				
				[newSplit setSplitTransaction:-2];
				[newSplit setIntValue:-2 forKey:@"Split"];
				
				[transIndex addChild:newSplit];
				
				[transactionsTableView reloadData];
				
				NSInteger row = [transactionsTableView rowForItem:newSplit];
				
				[transactionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
				[transactionsTableView scrollRowToVisible:row];
				
				[window makeFirstResponder:transactionsPayee];
			}
			else
			{
				[transactionsTableView reloadData];
			}
		}		
	}
	
	[numberFormatter release];
	
	m_UnsavedChanges = true;
	
	[self updateUI];
}

- (void)ScheduledSelectionDidChange:(NSNotification *)notification
{	
	NSIndexSet *rows = [scheduledTransactionsTableView selectedRowIndexes];
	
	if ([rows count] == 1)
	{
		[deleteScheduled setEnabled:YES];
		
		m_bEditing = true;
		
		NSInteger row = [rows lastIndex];

		NSMutableDictionary *item = [[m_aScheduledTransactions objectAtIndex:row] retain];
		
		ScheduledTransaction &schedTrans = m_Document.getScheduledTransaction(row);
		
		TransactionType eType = schedTrans.getType();
		
		Date date1 = schedTrans.getNextDate();
		NSDate *datetemp = convertToNSDate(date1);
		
		int account = schedTrans.getAccount();
		
		[scheduledPayee setStringValue:[item valueForKey:@"payee"]];
		[scheduledCategory setStringValue:[item valueForKey:@"category"]];
		
		std::string strDescription = schedTrans.getDescription();
		NSString *sDescription = [[NSString alloc] initWithUTF8String:strDescription.c_str()];
		[scheduledDescription setStringValue:sDescription];
		
		[scheduledAmount setStringValue:[item valueForKey:@"amount"]];
		
		Frequency eFreq = schedTrans.getFrequency();
		
		[scheduledFrequency selectItemAtIndex:eFreq];
		[scheduledType selectItemAtIndex:eType];
		
		[scheduledDateCntl setDateValue:datetemp];
		
		if (account >= 0)
		{
			[scheduledAccount selectItemAtIndex:account];
		}
	}
	else
	{
		m_bEditing = false;
		
		[deleteScheduled setEnabled:NO];
		
		[scheduledPayee setStringValue:@""];
		[scheduledCategory setStringValue:@""];
		[scheduledDescription setStringValue:@""];
		[scheduledAmount setStringValue:@""];
	}		
}

- (void)updateScheduled:(id)sender
{
	if (!m_bEditing)
		return;
	
	NSIndexSet *rows = [scheduledTransactionsTableView selectedRowIndexes];
	
	if ([rows count] != 1)
	{		
		return;
	}
	
	NSInteger row = [rows lastIndex];
	
	ScheduledTransaction &schedTrans = m_Document.getScheduledTransaction(row);
	
	NSDate *ndate1 = [scheduledDateCntl dateValue];
	NSCalendarDate *CalDate = [ndate1 dateWithCalendarFormat:0 timeZone:0];
	
	int nYear = [CalDate yearOfCommonEra];
	int nMonth = [CalDate monthOfYear];
	int nDay = [CalDate dayOfMonth];
	
	Date date1(nDay, nMonth, nYear);
	
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	NSString *sDate = [[dateFormatter stringFromDate:ndate1] retain];
	
	[dateFormatter release];
	
	std::string strPayee = [[scheduledPayee stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strDesc = [[scheduledDescription stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	std::string strCategory = [[scheduledCategory stringValue] cStringUsingEncoding:NSASCIIStringEncoding];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	[numberFormatter setLenient:YES];
	
	NSNumber *nAmount = [numberFormatter numberFromString:[scheduledAmount stringValue]];	
	fixed fAmount = [nAmount doubleValue];
	
	// reformat the number again, in case an abbreviation was used
	NSString *sAmount = [[numberFormatter stringFromNumber:nAmount] retain];
	
	int nType = [scheduledType indexOfSelectedItem];
	TransactionType eType = static_cast<TransactionType>(nType);
	
	int nAccount = [scheduledAccount indexOfSelectedItem];
	
	int nFrequency = [scheduledFrequency indexOfSelectedItem];
	Frequency eFreq = static_cast<Frequency>(nFrequency);
	
	// update the actual ScheduledTransaction
	
	schedTrans.setAccount(nAccount);
	schedTrans.setPayee(strPayee);
	schedTrans.setCategory(strCategory);
	schedTrans.setDescription(strDesc);
	schedTrans.setAmount(fAmount);
	schedTrans.setFrequency(eFreq);
	schedTrans.setNextDate(date1);
	schedTrans.setType(eType);
	
	NSMutableDictionary *oSchedTransItem = [m_aScheduledTransactions objectAtIndex:row];
	
	[oSchedTransItem setValue:[scheduledPayee stringValue] forKey:@"payee"];
	[oSchedTransItem setValue:[scheduledDescription stringValue] forKey:@"description"];
	[oSchedTransItem setValue:[scheduledCategory stringValue] forKey:@"category"];
	[oSchedTransItem setValue:sAmount forKey:@"amount"];
	[oSchedTransItem setValue:[scheduledFrequency titleOfSelectedItem] forKey:@"frequency"];
	[oSchedTransItem setValue:sDate forKey:@"nextdate"];
	[oSchedTransItem setValue:[scheduledAccount titleOfSelectedItem] forKey:@"account"];	
	
	[numberFormatter release];
	
	[scheduledTransactionsTableView reloadData];
	
	m_UnsavedChanges = true;	
}

- (IBAction)deleteMisc:(id)sender
{
	m_bEditing = false;
	
	int nGraph = [indexBar getItemIndex];
	
	if (nGraph >= 0)
	{
		NSString * message = @"The Graph will be deleted. Are you sure?";
		
		int choice = NSAlertDefaultReturn;
		
		choice = NSRunAlertPanel(@"Delete Graph?", message, @"Delete", @"Cancel", nil);
		
		if (choice != NSAlertDefaultReturn)
			return;
		
		m_Document.deleteGraph(nGraph);
		
		m_UnsavedChanges = true;
		
		[self buildIndexTree];
	}
	
}

- (IBAction)updateGraph:(id)sender
{
	if (!m_pGraph)
		return;
	
	int nAccount = [graphAccount indexOfSelectedItem];
	
	NSDate *nsStartDate = [graphStartDateCntrl dateValue];
	NSCalendarDate *nsCalStartDate = [nsStartDate dateWithCalendarFormat:0 timeZone:0];
	
	int nStartYear = [nsCalStartDate yearOfCommonEra];
	int nStartMonth = [nsCalStartDate monthOfYear];
	int nStartDay = [nsCalStartDate dayOfMonth];
	
	Date startDate(nStartDay, nStartMonth, nStartYear);
	
	NSDate *nsEndDate = [graphEndDateCntrl dateValue];
	NSCalendarDate *nsCalEndDate = [nsEndDate dateWithCalendarFormat:0 timeZone:0];
	
	int nEndYear = [nsCalEndDate yearOfCommonEra];
	int nEndMonth = [nsCalEndDate monthOfYear];
	int nEndDay = [nsCalEndDate dayOfMonth];
	
	Date endDate(nEndDay, nEndMonth, nEndYear);
	
	int nType = [graphType indexOfSelectedItem];
	GraphType eType = static_cast<GraphType>(nType);
	
	bool bIgnoreTransfers = false;
	
	if ([graphIgnoreTransfers state] == NSOnState)
		bIgnoreTransfers = true;
	
	m_pGraph->setAccount(nAccount);
	m_pGraph->setStartDate(startDate);
	m_pGraph->setEndDate(endDate);
	m_pGraph->setType(eType);
	m_pGraph->setIgnoreTransfers(bIgnoreTransfers);
	
	m_UnsavedChanges = true;
	
	[self buildGraph];
}

- (IBAction)showLast30DaysTransactions:(id)sender
{
	nShowTransactionsType = LAST_30DAYS;
	[self buildTransactionsTree];
}

- (IBAction)showAllTransactionsThisYear:(id)sender
{
	nShowTransactionsType = ALL_THIS_YEAR;
	[self buildTransactionsTree];
}

- (IBAction)showAllTransactions:(id)sender
{
	nShowTransactionsType = ALL;
	[self buildTransactionsTree];
}

- (IBAction)DeletePayee:(id)sender
{
	NSInteger row = [payeesTableView selectedRow];
	
	if (row >= 0)
	{
		NSString *sPayee = [m_aPayeeItems objectAtIndex:row];
		
		std::string strPayee = [sPayee cStringUsingEncoding:NSASCIIStringEncoding];
		
		[m_aPayeeItems removeObjectAtIndex:row];
		
		m_Document.deletePayee(strPayee);
		
		[payeesTableView reloadData];
		
		m_UnsavedChanges = true;
	}
}

- (IBAction)DeleteCategory:(id)sender
{
	NSInteger row = [categoriesTableView selectedRow];
	
	if (row >= 0)
	{
		NSString *sCategory = [m_aCategoryItems objectAtIndex:row];
		
		std::string strCategory = [sCategory cStringUsingEncoding:NSASCIIStringEncoding];
		
		[m_aCategoryItems removeObjectAtIndex:row];
		
		m_Document.deleteCategory(strCategory);
		
		[categoriesTableView reloadData];
		
		m_UnsavedChanges = true;
	}
}

- (IBAction)AddScheduledTransaction:(id)sender
{
	NSDate *ndate1 = [scheduledDateCntl dateValue];
	NSCalendarDate *CalDate = [ndate1 dateWithCalendarFormat:0 timeZone:0];
	
	int nYear = [CalDate yearOfCommonEra];
	int nMonth = [CalDate monthOfYear];
	int nDay = [CalDate dayOfMonth];
	
	Date date1(nDay, nMonth, nYear);
	
	ScheduledTransaction newST;
	newST.setNextDate(date1);
	
	int schedTransIndex = m_Document.addScheduledTransaction(newST);
	
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];

	NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
	
	std::string strSPayee = newST.getPayee();
	NSString *sSPayee = [[NSString alloc] initWithUTF8String:strSPayee.c_str()];
	
	std::string strSCategory = newST.getCategory();
	NSString *sSCategory = [[NSString alloc] initWithUTF8String:strSCategory.c_str()];
	
	NSNumber *nSAmount = [NSNumber numberWithDouble:newST.getAmount().ToDouble()];
	
	NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
	
	NSString *sSDate = [[dateFormatter stringFromDate:ndate1] retain];	
	
	[item setValue:[NSNumber numberWithInt:schedTransIndex] forKey:@"index"];
	[item setValue:sSPayee forKey:@"payee"];
	[item setValue:sSCategory forKey:@"category"];
	[item setValue:sSAmount forKey:@"amount"];
	[item setValue:sSDate forKey:@"nextdate"];
	[item setValue:[NSNumber numberWithBool:true] forKey:@"enabled"];
	
	[m_aScheduledTransactions addObject:item];
	
	[dateFormatter release];
	[numberFormatter release];
	
	[scheduledTransactionsTableView reloadData];
	
	NSInteger row = schedTransIndex;
	
	[scheduledTransactionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[scheduledTransactionsTableView scrollRowToVisible:row];
	
	[window makeFirstResponder:scheduledPayee];
	
	m_UnsavedChanges = true;
}

- (IBAction)DeleteScheduledTransaction:(id)sender
{
	NSInteger row = [scheduledTransactionsTableView selectedRow];
	
	if (row >= 0)
	{
		[m_aScheduledTransactions removeObjectAtIndex:row];
		m_Document.deleteScheduledTransaction(row);
	}
	
	[scheduledTransactionsTableView reloadData];
	m_UnsavedChanges = true;
}

- (IBAction)AddGraph:(id)sender
{
	Graph newGraph;
	newGraph.setName("New Graph");
	newGraph.setAccount(0);
	
	Date currentDate;
	currentDate.Now();
	
	newGraph.setStartDate(currentDate);
	
	currentDate.setDay(1);
	newGraph.setEndDate(currentDate);
	
	int nGraphNum = m_Document.addGraph(newGraph);
	
	NSString *sGraphKey = [NSString stringWithFormat:@"g@s", nGraphNum];
	
	[indexBar addItem:@"graphs" key:sGraphKey title:@"New Graph" item:nGraphNum action:@selector(graphSelected:) target:self type:3 rename:@selector(graphRenamed:) renameTarget:self];
	
	m_UnsavedChanges = true;
	
	[indexBar reloadData];
}

// Transactions OutlineView Start

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (item == nil)
	{
		return [m_aTransactionItems objectAtIndex:index];
	}
	else
	{
		return [(TransactionItem*)item childAtIndex:index];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [item expandable];
}

-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (item == nil)
	{
		if (outlineView == transactionsTableView)
		{
			return [m_aTransactionItems count];
		}
    }
	
    return [item childrenCount];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *identifier = [tableColumn identifier];
	
	if ([identifier caseInsensitiveCompare:@"reconciled"] == NSOrderedSame)
	{
		int nReconciled = [item intKeyValue:identifier];
		return [NSNumber numberWithInt:nReconciled];
	}

    return [item keyValue:identifier];
}

- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	NSString *identifier = [tableColumn identifier];
	
	if (item)
	{
		if (outlineView == transactionsTableView)
		{
			[item setValue:object forKey:identifier];
			
			int nTrans = [item transaction];
			//		int nSplit = [m_SelectedItem splitTransaction];
			
			Transaction *trans = NULL;
			//		SplitTransaction *split = NULL;
			
			if (nTrans >= 0)
				trans = &m_pAccount->getTransaction(nTrans);
			
			if ([identifier isEqualToString:@"Reconciled"])
			{
				if ([object boolValue] == YES)
				{
					trans->setReconciled(true);
				}
				else
				{
					trans->setReconciled(false);
				}
				
				m_UnsavedChanges = true;
				
				[self updateUI];
			}
		}
	}
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	BOOL result = NO;
	
	return result;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	if (outlineView != transactionsTableView)
	{
		return;
	}
	
	NSColor *fontColor;
	
	BOOL enableCheck = YES;
	
	if ([item intKeyValue:@"Split"] != -1)
		enableCheck = NO;
		
	if ([outlineView selectedRow] == [outlineView rowForItem:item])
	{
		fontColor = [NSColor whiteColor];
	}
	else
	{
		if ([item intKeyValue:@"Split"] == -2)
		{
			fontColor = [NSColor grayColor];
		}
		else
		{
			fontColor = [NSColor blackColor];
		}
	}
	
	if ([[tableColumn identifier] isEqualToString:@"Reconciled"])
	{
		if (enableCheck == YES)
		{
			[cell setImagePosition: NSImageOnly];
		}
		else
		{
			[cell setImagePosition: NSNoImage];
		}
	}
	else
		[cell setTextColor:fontColor];
}

// Transactions OutlineView End

// Payees/Categories/SchedTrans TableView Start

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	id result = @"";
	NSString *identifier = [aTableColumn identifier];
	
	if (aTableView == payeesTableView)
	{
		NSString *sPayee = [m_aPayeeItems objectAtIndex:rowIndex];
		
		if ([identifier isEqualToString:@"payee"])
		{		
			result = sPayee;
		}
	}
	else if (aTableView == categoriesTableView)
	{
		NSString *sCategory = [m_aCategoryItems objectAtIndex:rowIndex];
		
		if ([identifier isEqualToString:@"category"])
		{		
			result = sCategory;
		}
	}
	else if (aTableView == scheduledTransactionsTableView)
	{
		NSMutableDictionary *oObject = [m_aScheduledTransactions objectAtIndex:rowIndex];
		
		if ([identifier caseInsensitiveCompare:@"enabled"] == NSOrderedSame)
		{
			int nEnabled = [[oObject valueForKey:@"enabled"] intValue];
			return [NSNumber numberWithInt:nEnabled];
		}
		
		result = [oObject valueForKey:identifier];
	}
		
	return result;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if (aTableView == payeesTableView)
		return [m_aPayeeItems count];
	else if (aTableView == categoriesTableView)
		return [m_aCategoryItems count];
	else if (aTableView == scheduledTransactionsTableView)
		return [m_aScheduledTransactions count];
	
	return 0;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	NSString *identifier = [tableColumn identifier];
	
	if (aTableView == scheduledTransactionsTableView)
	{
		if ([identifier isEqualToString:@"enabled"])
		{
			int nRow = rowIndex;
			
			if (nRow < 0)
				return;
			
			NSMutableDictionary *nsSchedTrans = [m_aScheduledTransactions objectAtIndex:nRow];
			
			if (nsSchedTrans == nil)
				return;
			
			[nsSchedTrans setValue:[NSNumber numberWithBool:[object boolValue]] forKey:@"enabled"];
			
			ScheduledTransaction &oSchedTrans = m_Document.getScheduledTransaction(nRow);
			
			if ([object boolValue] == YES)
			{
				oSchedTrans.setEnabled(true);					
			}
			else
			{
				oSchedTrans.setEnabled(false);
			}
			
			m_UnsavedChanges = true;
		}			
	}
}

// Payees/Categories TableView End

NSDate * convertToNSDate(Date &date)
{
	NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    
    NSDateComponents *dateComponents = [[NSDateComponents alloc] init];
    [dateComponents setYear:date.Year()];
    [dateComponents setMonth:date.Month()];
    [dateComponents setDay:date.Day()];
    
    [dateComponents setHour:0];
    [dateComponents setMinute:0];
    [dateComponents setSecond:0];
	
	NSDate *nsDate = [gregorian dateFromComponents:dateComponents];
//	[dateComponents release];
//	[gregorian release];
	
    return nsDate;
}

- (IBAction)OpenFile:(id)sender
{
	if (m_UnsavedChanges)
    {
		int choice = NSAlertDefaultReturn;
		
		NSString *message = @"Do you want to save the changes you made in this document?";
		
		choice = NSRunAlertPanel(message, @"Your changes will be lost if you don't save them.", @"Save", @"Don't Save", @"Cancel");
		
		if (choice == NSAlertDefaultReturn) // Save file
		{
			[self SaveFile:sender];
		}
		else if (choice == NSAlertOtherReturn) // Cancel
		{
			return;
		}
    }
	
	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	NSString *fileToOpen;
	std::string strFile = "";
	[oPanel setAllowsMultipleSelection: NO];
	[oPanel setResolvesAliases: YES];
	[oPanel setTitle: @"Open Document"];
	[oPanel setAllowedFileTypes:[NSArray arrayWithObjects: @"stash", nil]];
	
	if ([oPanel runModal] == NSOKButton)
	{
		fileToOpen = [oPanel filename];
		strFile = [fileToOpen cStringUsingEncoding: NSASCIIStringEncoding];
		
		if ([self OpenFileAt:strFile] == false)
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:[NSString stringWithFormat:@"Could not open file: \"%@\".", fileToOpen]];
			[alert setInformativeText: @"There was a problem opening the Document file."];
			[alert setAlertStyle: NSWarningAlertStyle];
			[alert addButtonWithTitle: @"OK"];
			
			[alert runModal];
			[alert release];
			return;
		}
		
		[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileToOpen]];
		
		m_DocumentFile = strFile;
		m_UnsavedChanges = false;
		
		m_SelectedTransaction = 0;
		m_pAccount = 0;
		
		[self buildIndexTree];
		[self refreshLibraryItems];
		
		[self calculateAndShowScheduled];
	}
}

- (IBAction)SaveFile:(id)sender
{
	if (m_DocumentFile.empty())
	{
		[self SaveFileAs:sender];
	}
	else
	{
		if ([self SaveFileTo:m_DocumentFile] == true)
		{
			m_UnsavedChanges = false;
		}
	}
}

- (IBAction)SaveFileAs:(id)sender
{
	NSSavePanel *sPanel = [NSSavePanel savePanel];
	NSString *fileToSave;
	std::string strFile = "";
	
	[sPanel setTitle: @"Save Document"];
	[sPanel setRequiredFileType:@"stash"];
	[sPanel setAllowedFileTypes:[NSArray arrayWithObjects: @"stash", nil]];
	
	if ([sPanel runModal] == NSOKButton)
	{
		fileToSave = [sPanel filename];
		strFile = [fileToSave cStringUsingEncoding: NSASCIIStringEncoding];
		
		if ([self SaveFileTo:strFile] == false)
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:[NSString stringWithFormat:@"Could not save to file: \"%@\".", fileToSave]];
			[alert setInformativeText: @"There was a problem saving the Document to the file."];
			[alert setAlertStyle: NSWarningAlertStyle];
			[alert addButtonWithTitle: @"OK"];
			
			[alert runModal];
			[alert release];
		}
		else
		{
			[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileToSave]];
			
			m_DocumentFile = strFile;
			m_UnsavedChanges = false;
		}
	}
}

- (bool)OpenFileAt:(std::string)path
{
	std::fstream fileStream(path.c_str(), std::ios::in | std::ios::binary);
	
	if (!fileStream)
	{
		return false;;
	}
	
	if (!m_Document.Load(fileStream))
		return false;
	
	fileStream.close();
	
	return true;	
}

- (bool)SaveFileTo:(std::string)path
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GeneralCreateBackupOnSave"] == YES)
	{
		std::string strPathBackup = path;
		strPathBackup += ".bak";
		
		rename(path.c_str(), strPathBackup.c_str());
	}
	
	std::fstream fileStream(path.c_str(), std::ios::out | std::ios::binary | std::ios::trunc);
	
	if (!fileStream)
	{
		return false;
	}
	
	m_Document.Store(fileStream);
	
	fileStream.close();
	
	return true;
}

- (void)calculateAndShowScheduled
{
	NSMutableArray *array = [[NSMutableArray alloc] init];
	
	std::vector<ScheduledTransaction>::iterator it = m_Document.SchedTransBegin();
	
	int schedTransIndex = 0;
	
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterNoStyle];
	
	Date today;
	
	for (; it != m_Document.SchedTransEnd(); ++it, schedTransIndex++)
	{
		if (it->isEnabled() && it->getNextDate() <= today)
		{
			NSMutableDictionary *item = [[NSMutableDictionary alloc] init];
			
			std::string strSPayee = it->getPayee();
			NSString *sSPayee = [[NSString alloc] initWithUTF8String:strSPayee.c_str()];
			
			NSNumber *nSAmount = [NSNumber numberWithDouble:it->getAmount().ToDouble()];
			
			NSString *sSAmount = [[numberFormatter stringFromNumber:nSAmount] retain];
			
			NSDate *date = convertToNSDate(const_cast<Date&>(it->getNextDate2()));
			NSString *sSDate = [[dateFormatter stringFromDate:date] retain];
			
			int nAccount = it->getAccount();
			
			if (nAccount >= 0)
			{
				Account &oAccount = m_Document.getAccount(nAccount);
				std::string strAccount = oAccount.getName();
				NSString *sAccount = [[NSString alloc] initWithUTF8String:strAccount.c_str()];
				
				[item setValue:[NSNumber numberWithInt:schedTransIndex] forKey:@"index"];
				[item setValue:sSPayee forKey:@"payee"];
				[item setValue:sSAmount forKey:@"amount"];
				[item setValue:sSDate forKey:@"date"];
				[item setValue:sAccount forKey:@"account"];
				
				[array addObject:item];
			}
		}
	}
	
	[numberFormatter release];
	[dateFormatter release];
	
	if ([array count] > 0)
	{
		DueScheduledTransactionsController *dueSchedController = [[DueScheduledTransactionsController alloc] initWnd:self withArray:array];
	
		[dueSchedController showWindow:self];
	}
	
	[array release];
}

- (void)AddDueScheduledTransaction:(int)index
{
	Date today;
	
	ScheduledTransaction &schedTrans = m_Document.getScheduledTransaction(index);
	
	Transaction newTransaction(schedTrans.getDescription(), schedTrans.getPayee(), schedTrans.getCategory(), schedTrans.getAmount(), today);
	
	newTransaction.setType(schedTrans.getType());
	
	Account &oAccount = m_Document.getAccount(schedTrans.getAccount());
	
	oAccount.addTransaction(newTransaction);
	
	m_UnsavedChanges = true;
	
	[self buildTransactionsTree];
	
	schedTrans.AdvanceNextDate();	
}

- (void)SkipDueScheduledTransaction:(int)index
{
	ScheduledTransaction &schedTrans = m_Document.getScheduledTransaction(index);
	
	schedTrans.AdvanceNextDate();	
}

- (IBAction)ImportQIF:(id)sender
{
	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	NSString *fileToOpen;
	std::string strFile = "";
	[oPanel setAllowsMultipleSelection: NO];
	[oPanel setResolvesAliases: YES];
	[oPanel setTitle: @"Import QIF file"];
	[oPanel setAllowedFileTypes:[NSArray arrayWithObjects: @"qif", nil]];
	
	if ([oPanel runModal] == NSOKButton)
	{
		fileToOpen = [oPanel filename];
		strFile = [fileToOpen cStringUsingEncoding: NSASCIIStringEncoding];
		
		std::string strDateSample = "";
		NSString *sDateSample = @"";
		
		if (getDateFormatSampleFromQIFFile(strFile, strDateSample))
		{
			sDateSample = [[NSString alloc] initWithUTF8String:strDateSample.c_str()];
		}
		
		ImportQIFController *importQIFController = [[ImportQIFController alloc] initWnd:self withFile:fileToOpen sampleFormat:sDateSample];
		[importQIFController showWindow:self];
	}
}

- (void)importQIFConfirmed:(ImportQIFController *)importQIFController
{
	int nDateFormat = [importQIFController dateFormat];
	DateStringFormat dateFormat = static_cast<DateStringFormat>(nDateFormat);
	
	char cSeparator = [importQIFController separator];
	
	NSString *sFile = [importQIFController file];
		
	std::string strFile = [sFile cStringUsingEncoding: NSASCIIStringEncoding];
	
	[importQIFController release];
	
	if (importQIFFileToAccount(m_pAccount, strFile, dateFormat, cSeparator))
		[self buildTransactionsTree];	
}

- (IBAction)ExportQIF:(id)sender
{
	NSSavePanel *sPanel = [NSSavePanel savePanel];
	NSString *fileToSave;
	std::string strFile = "";
	
	[sPanel setTitle: @"Export to QIF file"];
	[sPanel setRequiredFileType:@"qif"];
	[sPanel setAllowedFileTypes:[NSArray arrayWithObjects: @"qif", nil]];
	
	if ([sPanel runModal] == NSOKButton)
	{
		fileToSave = [sPanel filename];
		strFile = [fileToSave cStringUsingEncoding: NSASCIIStringEncoding];
		
		exportAccountToQIFFile(m_pAccount, strFile, UK);
	}	
}

- (IBAction)showPreferencesWindow:(id)sender
{
	NSWindow *window1 = [prefController window];
    if (![window1 isVisible])
        [window1 center];
	
    [window1 makeKeyAndOrderFront:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	if (m_UnsavedChanges)
    {
		int choice = NSAlertDefaultReturn;
		
		NSString *message = @"Do you want to save the changes you made in this document?";
		
		choice = NSRunAlertPanel(message, @"Your changes will be lost if you don't save them.", @"Save", @"Don't Save", @"Cancel");
		
		if (choice == NSAlertDefaultReturn) // Save file
		{
			[self SaveFile:sender];
			return NSTerminateNow;
		}
		else if (choice == NSAlertOtherReturn) // Cancel
		{
			return NSTerminateLater;
		}
    }
	
    return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	// save the window size and position
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	
	[defs setFloat:[window frame].origin.x forKey:@"MainWndPosX"];
	[defs setFloat:[window frame].origin.y forKey:@"MainWndPosY"];
	[defs setFloat:[window frame].size.width forKey:@"MainWndWidth"];
	[defs setFloat:[window frame].size.height forKey:@"MainWndHeight"];
	
	// Save Transactions view OutlineView column sizes
	int nCol = 0;
	for (NSTableColumn *tc in [transactionsTableView tableColumns])
	{
		float fWidth = [tc width];
		NSString *sColKey = [NSString stringWithFormat:@"TransactionColWidth%i", nCol++];
		
		[defs setFloat:fWidth forKey:sColKey];
	}
	
	[m_aTransactionItems release];
	[m_aPayeeItems release];
	[m_aCategoryItems release];
	[m_aScheduledTransactions release];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if (!m_HasFinishedLoading)
	{
		// App hasn't finished loading, and Cocoa gets sent this before the app's finished loading
		// (via the command line), so we have to do things like this, otherwise things are out of sync
		
		m_sPendingOpenFile = filename;
		return NO;
	}
	
	if (m_UnsavedChanges)
    {
		int choice = NSAlertDefaultReturn;
		
        NSString * message = @"You have unsaved changes in this document. Are you sure you want to open another document?";
		
		choice = NSRunAlertPanel(@"Replace current document?", message, @"Replace", @"Cancel", nil);
		
		if (choice != NSAlertDefaultReturn)
			return NO;
    }
	
	std::string strFile = [filename cStringUsingEncoding: NSASCIIStringEncoding];
	
	if ([self OpenFileAt:strFile] == false)
	{
		return NO;
	}
	
	[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filename]];
	
	m_DocumentFile = strFile;
	m_UnsavedChanges = false;
	
	[self buildIndexTree];
	[self refreshLibraryItems];
	
	[self calculateAndShowScheduled];

	return YES;
}

- (void)updateBalancesFromTransactionIndex:(int)nIndex
{
	NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
	[numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
	
	fixed localBalance = 0.0;
	
	nIndex -= m_nTransactionOffset;
	
	m_aBalance.erase(m_aBalance.begin() + nIndex, m_aBalance.end());
	
	if (nIndex == 0)
	{
		localBalance = m_pAccount->getBalance(true, m_nTransactionOffset);
	}
	else
	{
		localBalance = m_aBalance.back();
	}
	
	std::vector<Transaction>::iterator it = m_pAccount->begin() + m_nTransactionOffset + nIndex;
	
	int nTransItemIndex = nIndex;
	for (; it != m_pAccount->end(); ++it, nTransItemIndex++)
	{
		TransactionItem *aTransaction = [m_aTransactionItems objectAtIndex:nTransItemIndex];
		
		localBalance += it->Amount();
		
		m_aBalance.push_back(localBalance);
		
		NSNumber *nTBalance = [NSNumber numberWithDouble:localBalance.ToDouble()];
		NSString *sTBalance = [[numberFormatter stringFromNumber:nTBalance] retain];
				
		[aTransaction setValue:sTBalance forKey:@"Balance"];		
	
		[sTBalance release];
	}	

	[numberFormatter release];
}

@end
