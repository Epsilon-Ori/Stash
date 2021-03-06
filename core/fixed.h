/* Fixed point decimal class datatype
 */

/* Based on decimal.h/cpp by Taj Morton.
 */

#ifndef FIXED_H
#define FIXED_H

#include <string>

enum CurrencyFormat
{
	UKFormat,
	EuropeFormat
};

class fixed
{
public:
	fixed(const double value = 0.00);
	fixed(const std::string& value, CurrencyFormat format = UKFormat);
	
	fixed & operator=(const double & rhs);
	
	fixed operator+(const fixed & rhs) const;
	fixed & operator+=(const fixed & rhs);
	
	fixed operator-(const fixed & rhs) const;
	fixed & operator-=(const fixed & rhs);
	
	fixed operator*(const fixed & rhs) const;
	fixed & operator*=(const fixed & rhs);
	
	fixed operator/(const fixed & rhs) const;
	fixed & operator/=(const fixed & rhs);
	
	bool operator>(const fixed & rhs) const;	
	bool operator<(const fixed & rhs) const;	
	bool operator==(const fixed & rhs) const;
	bool operator!=(const fixed & rhs) const;
	
	// by value on purpose...
	void SetFromString(std::string value, CurrencyFormat format = UKFormat);
	
	bool IsZero() const;	
	bool IsPositive() const;
	
	void setPositive() { m_positive = true; }
	void setNegative() { m_positive = false; }
	
	void Load(std::fstream& stream, int version);
	void Store(std::fstream& stream) const;
	
	friend std::ostream& operator<< (std::ostream & os, const fixed & d);
	friend std::istream& operator>> (std::istream & stream, fixed & d);
	
	double ToDouble() const;
	double ToDoubleAbs() const;
	operator std::string() const;
	
	// 
	unsigned int GetNumDigits() const;
	
private:
	bool m_positive;
	
	unsigned short int m_precision;
	unsigned long int m_num;
	
	std::string ToString() const;
	
	void SetFromDouble(const double value = 0.00);	
	
	static void add(fixed & dec, const fixed & value);
	static void subtract(fixed & dec, const fixed & value);
	static void multiply(fixed & dec, const fixed & value);
	static void divide(fixed & dec, const fixed & value);
};

#endif
