/* 
 * Stash:  A Personal Finance app (core).
 * Copyright (C) 2009-2020 Peter Pearson
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

#ifndef SPLITTRANSACTION_H
#define SPLITTRANSACTION_H

#include "fixed.h"
#include <string>

class SplitTransaction
{
public:
	SplitTransaction() { }
	SplitTransaction(const std::string& Description, const std::string& Payee, const std::string& Category, fixed Amount);
	
	const std::string& getDescription() const
	{
		return m_Description;
	}

	void setDescription(const std::string& Description)
	{
		m_Description = Description;
	}

	const std::string& getPayee() const
	{
		return m_Payee;
	}

	void setPayee(const std::string& Payee)
	{
		m_Payee = Payee;
	}

	const std::string& getCategory() const
	{
		return m_Category;
	}

	void setCategory(const std::string& Category)
	{
		m_Category = Category;
	}

	fixed getAmount() const
	{
		return m_Amount;
	}

	void setAmount(fixed Amount)
	{
		m_Amount = Amount;
	}
	
	void Load(std::fstream &stream, int version);
	void Store(std::fstream &stream) const;

private:
	
	std::string m_Description;
	std::string m_Payee;
	std::string m_Category;
	fixed m_Amount;

};
#endif // SPLITTRANSACTION_H
