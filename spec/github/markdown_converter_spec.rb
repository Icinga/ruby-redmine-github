require 'spec_helper'
require 'redmine'
require 'redmine/markdown_converter'

describe Redmine::MarkdownConverter do
  let :icingaweb2_example do
    'After i enable the Director, and click on the "Icinga Director" i get a Waring "No database resource has been configured yet. Please click here to complete your config"
If i click on "click here" i got a Dump:

Plugin by name \'Note\' was not found in the registry; used paths:
Zend_Form_Element_: Zend/Form/Element/

#0 /usr/share/php/Zend/Form.php(1111): Zend_Loader_PluginLoader->load(\'note\')
#1 /usr/share/php/Zend/Form.php(1040): Zend_Form->createElement(\'note\', \'_HINT1\', Array)
#2 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(216): Zend_Form->addElement(\'note\', \'_HINT1\', Array)
#3 /usr/share/icingaweb2/modules/director/application/forms/ConfigForm.php(19): Icinga\Module\Director\Web\Form\QuickForm->addHtml(\'<h3>Database ba...\')
#4 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(307): Icinga\Module\Director\Forms\ConfigForm->setup()
#5 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(431): Icinga\Module\Director\Web\Form\QuickForm->prepareElements()
#6 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(439): Icinga\Module\Director\Web\Form\QuickForm->setRequest(Object(Icinga\Web\Request))
#7 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(447): Icinga\Module\Director\Web\Form\QuickForm->getRequest()
#8 /usr/share/icingaweb2/modules/director/library/Director/Web/Form/QuickForm.php(322): Icinga\Module\Director\Web\Form\QuickForm->hasBeenSent()
#9 /usr/share/icingaweb2/modules/director/application/controllers/SettingsController.php(17): Icinga\Module\Director\Web\Form\QuickForm->handleRequest()
#10 /usr/share/php/Zend/Controller/Action.php(516): Icinga\Module\Director\Controllers\SettingsController->indexAction()
#11 /usr/share/php/Icinga/Web/Controller/Dispatcher.php(76): Zend_Controller_Action->dispatch(\'indexAction\')
#12 /usr/share/php/Zend/Controller/Front.php(954): Icinga\Web\Controller\Dispatcher->dispatch(Object(Icinga\Web\Request), Object(Icinga\Web\Response))
#13 /usr/share/php/Icinga/Application/Web.php(383): Zend_Controller_Front->dispatch(Object(Icinga\Web\Request), Object(Icinga\Web\Response))
#14 /usr/share/php/Icinga/Application/webrouter.php(109): Icinga\Application\Web->dispatch()
#15 /usr/share/icingaweb2/public/index.php(4): require_once(\'/usr/share/php/...\')
#16 {main}

The same Error if i click on "Configuration"-Tab in Configuration -> Modules -> director -> Configuration

Has this anything to do with https://dev.icinga.org/issues/7309?

Database: PostgreSQL
Icingaweb2: 2.2.0
Icings2: 2.4.3.1
Source: https://github.com/Icinga/icingaweb2-module-director

Thank you,
Uwe'
  end

  describe '.prepare' do
    it 'should try to fix Icinga web2 stacktraces outside a codeblock' do
      expect(subject.prepare(icingaweb2_example)).to match(/^<pre>\r?\n((?:^#\d+ .*?\r?\n)+)<\/pre>/m)
    end
  end
end
