/// Small bundled list for name suggestions when adding stock. Owners can
/// always type any other name.
class CatalogItem {
  final String name, generic, maker, form;
  const CatalogItem(this.name, this.generic, this.maker, this.form);
}

const medicineCatalog = [
  CatalogItem('নাপা ৫০০ মি.গ্রা.', 'প্যারাসিটামল', 'বেক্সিমকো', 'ট্যাবলেট'),
  CatalogItem('নাপা এক্সট্রা', 'প্যারাসিটামল + ক্যাফেইন', 'বেক্সিমকো', 'ট্যাবলেট'),
  CatalogItem('নাপা সিরাপ', 'প্যারাসিটামল', 'বেক্সিমকো', 'সিরাপ'),
  CatalogItem('ওমিপ্রাজল ২০', 'ওমিপ্রাজল', 'স্কয়ার', 'ক্যাপসুল'),
  CatalogItem('সারজেল ২০', 'এসোমিপ্রাজল', 'স্কয়ার', 'ট্যাবলেট'),
  CatalogItem('ফেক্সো ১২০', 'ফেক্সোফেনাডিন', 'স্কয়ার', 'ট্যাবলেট'),
  CatalogItem('মন্টিনেক্স ১০', 'মন্টেলুকাস্ট', 'এসকেএফ', 'ট্যাবলেট'),
  CatalogItem('সিপ্রোসিন ৫০০', 'সিপ্রোফ্লক্সাসিন', 'ইনসেপ্টা', 'ট্যাবলেট'),
  CatalogItem('ভিটামিন ডি ৪০০০', 'কোলক্যালসিফেরল', '', 'ক্যাপসুল'),
];
