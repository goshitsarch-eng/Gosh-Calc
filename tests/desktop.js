// Automation only. All domain/application behavior remains in Rust.
const wait = (ms = 90) => new Promise(resolve => setTimeout(resolve, ms));
const checks = [];
const assert = (condition, name) => { if (!condition) throw new Error(name); checks.push(name); };
const revision = () => document.querySelector('.app').dataset.testRevision;
const changed = async before => {
    for (let attempt=0; attempt<100; attempt++) {
        if (revision() !== before) { await wait(15); return; }
        await wait(20);
    }
    throw new Error('The native command did not finish');
};
const click = async selector => {
    const element = document.querySelector(selector);
    if (!element || element.disabled) throw new Error(`Unavailable control: ${selector}`);
    const before = revision(); element.click(); await changed(before);
};
const command = name => click(`[data-command="${name}"]`);
const mode = name => click(`[data-mode="${name}"]`);
const result = () => document.querySelector('#result').textContent.trim();
const enter = async text => {
    const app = document.querySelector('.app'); app.focus();
    for (const key of text) {
        const before = revision();
        app.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles:true, cancelable:true}));
        await changed(before);
    }
    await wait();
};
try {
    await mode('Standard'); await command('Clear calculation');
    await enter('12+3*4='); assert(result() === '24','shifted keyboard arithmetic and precedence');
    await click('[aria-label="Copy result"]');
    assert(document.querySelector('[role=status]')?.textContent.includes('Copied'),'copy result callback');
    await command('Clear calculation'); await enter('2+3=='); assert(result() === '8','repeat equals');
    await command('Clear calculation'); await enter('100+10%='); assert(result() === '110','contextual percent');
    await command('Clear calculation'); await enter('1/0='); assert(result() === 'Error','division by zero');
    await enter('7'); assert(result() === '7','error recovery');
    await command('Square'); assert(result() === '49','square button');
    await command('Square root'); assert(result() === '7','square root button');
    await command('Toggle sign'); assert(result() === '-7','sign toggle');
    await command('Clear calculation'); await enter('123'); await command('Backspace');
    assert(result() === '12','backspace'); await command('Clear entry'); assert(result() === '0','clear entry');
    await mode('Scientific'); await command('Clear calculation'); await enter('(2+3)*4=');
    assert(result() === '20','scientific parentheses');
    await command('Clear calculation'); await enter('30');
    if (document.querySelector('.angle').textContent.trim() !== 'DEG') await click('.angle');
    await command('Sine'); assert(result() === '0.5','degree trigonometry');
    await command('Inverse sine'); assert(result() === '30','inverse trigonometry');
    await command('Clear calculation'); await enter('5'); await command('Scientific notation'); await enter('3=');
    assert(result() === '5000','EE entry');
    await command('Clear calculation'); await command('Last answer'); assert(result() === '5000','Ans recall');
    await command('Clear calculation'); await command('Pi'); assert(result().startsWith('3.14159'),'pi constant');
    await command('Clear calculation'); await enter('3'); await command('Factorial'); assert(result() === '6','factorial');
    const unaryCases = [
        ['Square','2',4], ['Cube','2',8], ['Square root','9',3],
        ['Cube root','27',3], ['Reciprocal','4',0.25], ['Factorial','5',120],
        ['Sine','30',0.5], ['Cosine','60',0.5], ['Tangent','45',1],
        ['Natural logarithm','1',0], ['Inverse sine','0.5',30],
        ['Inverse cosine','0.5',60], ['Inverse tangent','1',45],
        ['Logarithm','100',2], ['Exponential','1',Math.E],
        ['Power of ten','2',100], ['Absolute value','2',2]
    ];
    for (const [name,input,expected] of unaryCases) {
        await command('Clear calculation'); await enter(input);
        if (name === 'Absolute value') await command('Toggle sign');
        await command(name);
        assert(Math.abs(Number(result()) - expected) < 1e-9, `${name} numeric callback`);
    }
    for (const [name,input,operand,expected] of [['Power','2','3','8'],['Nth root','27','3','3']]) {
        await command('Clear calculation'); await enter(input); await command(name); await enter(operand); await command('Equals');
        assert(result() === expected,`${name} numeric callback`);
    }
    await command('Clear calculation'); await command("Euler's number");
    assert(Math.abs(Number(result()) - Math.E) < 1e-9,'Euler constant callback');
    await command('Toggle angle unit'); assert(document.querySelector('.angle').textContent.trim() === 'RAD','RAD selector');
    await command('Clear calculation'); await command('Pi'); await command('Sine');
    assert(Math.abs(Number(result())) < 1e-9,'radian trigonometry'); await command('Toggle angle unit');
    // Traverse every scientific control after the numeric callback assertions.
    const scientific = [...document.querySelectorAll('.keypad button')].map(b=>b.getAttribute('data-command'));
    for (const name of scientific) {
        await command('Clear calculation'); await enter('2');
        const control = document.querySelector(`[data-command="${name}"]`);
        if (!control.disabled) await command(name);
    }
    checks.push(`scientific control traversal (${scientific.length})`);
    await mode('Programmer'); await command('Clear calculation'); await click('[data-base="HEX"]');
    await enter('FF+1='); assert(result() === '100','programmer HEX arithmetic');
    await click('[data-base="DEC"]'); assert(result() === '256','base conversion');
    await click('[aria-label="History"]'); await click('.history-entry');
    assert(result() === '256','numeric history recall across bases'); await click('[aria-label="Close history"]');
    await click('[data-base="BIN"]');
    assert(document.querySelector('[data-command="2"]').disabled,'invalid binary digit disabled');
    await click('[data-base="OCT"]'); assert(document.querySelector('[data-command="8"]').disabled,'invalid octal digit disabled');
    await click('[data-base="DEC"]'); await command('Clear calculation'); await enter('5&3=');
    assert(result() === '1','bitwise AND');
    for (const [name,input,operand,expected] of [
        ['Shift left','2','3','16'], ['Shift right','16','2','4'],
        ['Bitwise AND','5','3','1'], ['Bitwise OR','5','2','7'],
        ['Bitwise XOR','5','3','6'], ['Modulo','17','5','2']
    ]) {
        await command('Clear calculation'); await enter(input); await command(name); await enter(operand); await command('Equals');
        assert(result() === expected,`${name} numeric callback`);
    }
    await command('Clear calculation'); await enter('5'); await command('Bitwise NOT');
    assert(result() === '-6','bitwise NOT callback');
    await command('Clear calculation'); await click('[data-base="HEX"]');
    for (const digit of 'ABCDEF') await command(digit);
    assert(result() === 'ABCDEF','all hexadecimal digit callbacks'); await click('[data-base="DEC"]');
    await command('Clear calculation'); await enter('9007199254740993+1=');
    assert(result() === '9007199254740994','integer arithmetic beyond f64 precision');
    await click('[aria-label="Settings"]');
    for (const theme of ['light','dark','system']) {
        await click(`[data-theme-choice="${theme}"]`);
        assert(document.querySelector('.app').dataset.theme === theme,`${theme} theme updates immediately`);
    }
    await click('[aria-label="Close dialog"]');
    await click('[aria-label="Keyboard shortcuts"]');
    assert(document.querySelector('.shortcuts').textContent.includes('Enter'),'shortcut dialog'); await click('.dialog-done');
    await click('[aria-label="History"]'); await click('.clear-history');
    assert(document.querySelector('.clear-history').disabled,'empty history clear disabled'); await click('[aria-label="Close history"]');
    const keys = [...document.querySelectorAll('.keypad button')];
    assert(keys.every(b=>b.getAttribute('aria-label')&&b.getAttribute('title')),'accessible keypad labels and tooltips');
    assert(keys.every(b=>b.getBoundingClientRect().height >= 40),'readable keypad height');
    assert(document.documentElement.scrollWidth <= window.innerWidth,'no horizontal page overflow');
    await mode('Standard'); await command('Clear calculation');
    for (const digit of '0123456789') await command(digit);
    assert(result() === '123456789','all decimal digit callbacks');
    for (const [name,operand,expected] of [['Add','1','9'], ['Subtract','1','7'], ['Multiply','2','16'], ['Divide','2','4']]) {
        await command('Clear calculation'); await command('8'); await command(name); await command(operand); await command('Equals');
        assert(result() === expected,`${name} standard callback`);
    }
    await command('Clear calculation'); await command('1'); await command('Decimal point'); await command('5');
    assert(result() === '1.5','decimal point callback');
    await click('[aria-label="History"]'); await click('.clear-history'); await click('[aria-label="Close history"]');
    await command('Clear calculation'); await enter('24');
    dioxus.send({passed:true, checks}); await dioxus.recv(); return;
} catch(error) {
    dioxus.send({passed:false, checks, error:String(error), result:result()}); await dioxus.recv();
}
